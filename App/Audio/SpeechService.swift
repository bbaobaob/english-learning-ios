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
    /// This is the **direct** path: no file, no scrubber, no background
    /// survival. It is correct for the case it exists for — a one-shot tap on an
    /// example sentence or a vocabulary word, where a rendered file would cost
    /// a perceptible delay for a clip the learner will never scrub. Anything
    /// that needs transport controls or the lock screen goes through
    /// ``SpeechFileRenderer`` instead; see ``AudioPlayerModel``.
    ///
    /// Any utterance already in flight is stopped first, so a rapid second tap
    /// replaces the first rather than queueing behind it.
    ///
    /// - Parameters:
    ///   - text: What to say. Empty text is a no-op, not a silent crash.
    ///   - rate: A rate already resolved through ``SpeechRate``. Values outside
    ///     the system's range are clamped by ``SpeechRate/scaled(_:)``, because
    ///     an out-of-range rate is *silently ignored* rather than clamped by the
    ///     framework.
    ///   - voiceID: Optional voice override. Ignored when the identifier does
    ///     not match an installed voice — a content file naming a voice the
    ///     device does not have must degrade to the default, not fail.
    ///   - completion: Run on the main actor when the utterance ends or is cut
    ///     short, so callers do not need to reason about which happened.
    public func speak(
        _ text: String,
        rate: Float,
        voiceID: String? = nil,
        completion: (() -> Void)? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.completion?()
            self.completion = nil
            return
        }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        self.completion = completion

        let utterance = makeUtterance(text: trimmed, rate: rate, voiceID: voiceID)
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Builds a fully configured utterance.
    ///
    /// Shared with the renderer path so a sentence sounds identical whether it
    /// is played live or played from a cache file. **Every property is set here,
    /// before the utterance is handed to `speak(_:)` or `write(_:toBufferCallback:)`** —
    /// the framework reads `rate`, `voice`, and the delays at enqueue time, so a
    /// later assignment is not a late update, it is a no-op.
    func makeUtterance(text: String, rate: Float, voiceID: String?) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = min(max(rate, SpeechRate.minimum), SpeechRate.maximum)
        if let voiceID, let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        }
        // No pre-delay, so a tap on a list of examples feels immediate. A short
        // post-delay gives the synthesizer time to release the audio session
        // cleanly before the next utterance is enqueued, which is what stops a
        // fast sequence of taps from clipping the start of each word.
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0.1
        return utterance
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
