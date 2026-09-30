import SwiftUI
import EnglishCore

/// The one place this lane speaks text aloud.
///
/// The contract fixes `SpeechPlaying` but not the exact surface of
/// `AppState.audio`, so every play call funnels through here.
// TODO(design-system-lane): if AppState exposes speak(text:) / speak(_:rate:)
// directly, delete `SpeakGate` and call the service at the call sites.
enum SpeakGate {

    /// Speaks `text` at the normal content rate.
    ///
    /// `rate` is a multiplier of the system's own rate, never an absolute value.
    /// `AVSpeechUtterance.defaultSpeakingRate` is not a documented constant — it
    /// varies by OS version, locale, and installed voice — so a hardcoded `0.5`
    /// is a guess that sounds plausible on the developer's device and is too fast
    /// or too slow on everyone else's, with nothing to reveal the error.
    ///
    /// - Parameter rate: 1.0 is normal, 0.5 is half. Clamped to the bounds the
    ///   system reports, because an out-of-range rate is *silently ignored*
    ///   rather than clamped for you.
    @MainActor
    static func say(_ text: String, using app: AppState, rate: Double = 1.0) {
        app.audio.speak(text, rate: SpeechRate.scaled(rate))
    }

    /// Speaks `text` at an already-resolved absolute rate.
    ///
    /// For the one caller that has a `Float` in hand — ``slowRate`` — and would
    /// otherwise have to guess a multiplier to convert it back. Going through
    /// an absolute rate here is safe because ``slowRate`` was itself produced by
    /// ``SpeechRate/scaled(_:)`` and is therefore already clamped.
    @MainActor
    static func say(_ text: String, using app: AppState, absoluteRate: Float) {
        app.audio.speak(text, rate: absoluteRate)
    }

    /// The slow rate used by every "play slowly" control in this lane.
    ///
    /// Six-tenths of normal: slow enough to catch a word missed the first time,
    /// fast enough that the whole sentence still sounds like speech. The
    /// dictation flow's own "slow replay" goes further — see
    /// ``AudioPlayerModel/slowReplay()``, which plays a *rendered file* and so
    /// can go below the synthesizer's floor entirely.
    static let slowRate: Float = SpeechRate.scaled(0.6)
}
