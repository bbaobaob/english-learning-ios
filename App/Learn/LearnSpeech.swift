import SwiftUI
import EnglishCore

/// The one place this lane speaks text aloud.
///
/// The contract fixes `SpeechPlaying` but not the exact surface of
/// `AppState.audio`, so every play call funnels through here.
// TODO(design-system-lane): if AppState exposes speak(text:) / speak(_:rate:)
/// directly, delete `SpeakGate` and call the service at the call sites.
enum SpeakGate {

    /// Speaks `text` at the normal content rate.
    @MainActor
    static func say(_ text: String, using app: AppState, rate: Float = 0.5) {
        app.audio.speak(text, rate: rate)
    }

    /// The slow rate used by every "play slowly" control in this lane.
    /// 0.3 is the slow rate named in `AudioClip` and the content contract.
    static let slowRate: Float = 0.3
}

/// A short-lived "the speaker is talking" flag for a tappable example.
@MainActor
@Observable
final class SpeechPulse {
    private(set) var isSpeaking: Bool = false

    /// Speaks `text` and holds the pulse briefly, then clears it.
    func speak(_ text: String, using app: AppState, rate: Float) {
        app.audio.speak(text, rate: rate)
        isSpeaking = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.isSpeaking = false
        }
    }
}
