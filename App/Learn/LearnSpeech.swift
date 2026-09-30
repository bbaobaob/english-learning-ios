import SwiftUI
import EnglishCore

/// The one place this lane speaks text aloud.
///
/// The contract fixes `SpeechPlaying` but not the exact surface of
/// `AppState.audio`, so every play call funnels through here. `AppState` owns the
/// single `SpeechService`; this is a thin seam over it, not a second engine —
/// it exists so this lane has one place to change if the speech surface moves,
/// and so no call site in here has to know a rate is a multiplier.
///
/// ponytail: kept as an enum of statics rather than promoted onto `AppState`,
/// because `AppState` is the one type every lane shares and adding a lane's
/// vocabulary there is how it grows ten ways to speak. If a *second* lane needs
/// the same seam, promote it then.
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
    /// Named once in ``SpeechRate/replay`` so this lane and the audio lane cannot
    /// disagree about how slow "slowly" is. The dictation flow's own "slow
    /// replay" goes further — see ``AudioPlayerModel/slowReplay()``, which plays a
    /// *rendered file* and so can go below the synthesizer's floor entirely.
    static let slowRate: Float = SpeechRate.replay
}
