import Foundation
import AVFoundation
import Observation

/// The app's single speech synthesizer.
///
/// There is exactly one of these, owned by `AppState` and passed into
/// ``AudioPlayerModel``. That is not tidiness, it is a correctness requirement:
/// two live `AVSpeechSynthesizer` instances do not queue, they interleave, and
/// the result is two half-sentences spoken at once. One instance, one voice.
@MainActor
@Observable
public final class SpeechService {

    /// `true` while an utterance is in flight.
    public private(set) var isSpeaking: Bool = false

    /// Called when an utterance ends, whether naturally or by `stop()`.
    /// The audio player uses this to advance its repeat counter.
    @ObservationIgnored
    var onFinish: (() -> Void)?

    @ObservationIgnored
    private let synthesizer = AVSpeechSynthesizer()

    @ObservationIgnored
    private var completion: (() -> Void)?

    public init() {
        synthesizer.delegate = self
    }

    /// Speaks `text`.
    ///
    /// Any utterance already in flight is stopped first, so a rapid second tap
    /// replaces the first rather than queueing behind it.
    ///
    /// - Parameters:
    ///   - text: What to say. Empty text is a no-op, not a silent crash.
    ///   - rate: `AVSpeechUtterance.defaultSpeakingRate` is the normal speed.
    ///   - completion: Run on the main actor when the utterance ends or is cut
    ///     short, so callers do not need to reason about which happened.
    public func speak(_ text: String, rate: Float, completion: (() -> Void)? = nil) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.completion?()
            self.completion = nil
            return
        }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        self.completion = completion

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(rate, AVSpeechUtteranceMaximumSpeechRate))
        // `preUtteranceDelay` of 0 keeps a tap on a list of examples feeling
        // immediate; the synthesiser's own startup is short enough.
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0.1
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Stops the current utterance. Safe to call when nothing is speaking.
    public func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in self?.finish() }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in self?.finish() }
    }

    private func finish() {
        isSpeaking = false
        let callback = completion
        completion = nil
        onFinish?()
        callback?()
    }
}
