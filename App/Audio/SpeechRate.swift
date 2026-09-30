import Foundation
import AVFoundation

/// The app's speech rates, derived from the system's own constants at runtime.
///
/// **Why nothing here is a literal.** Apple's documentation does not print the
/// values of `AVSpeechUtteranceDefaultSpeechRate`,
/// `AVSpeechUtteranceMinimumSpeechRate`, or
/// `AVSpeechUtteranceMaximumSpeechRate`, and they differ between OS versions,
/// locales, and installed voices. A hardcoded `0.5` is a guess that happens to
/// work on the developer's device and is quietly too fast or too slow on
/// everyone else's — and because the real default is around `0.5`, a wrong
/// literal still *sounds* plausible, which is what makes the bug survive.
///
/// Every rate in the app is therefore a **multiple of the default**, clamped to
/// the bounds the system actually reports. That way a preset keeps its meaning
/// ("half speed", "a quarter speed") on any device, and an OS that changes its
/// range cannot produce a silent no-op.
enum SpeechRate {

    /// The system's normal speaking rate.
    ///
    /// Read through the typed `AVSpeechUtterance` spelling rather than the
    /// `AVSpeechUtteranceDefaultSpeechRate` global, which is what Swift exposes
    /// to this framework version.
    static var normal: Float { AVSpeechUtterance.defaultSpeakingRate }

    /// The slowest rate the system will honour.
    static var minimum: Float { AVSpeechUtterance.minimumSpeechRate }

    /// The fastest rate the system will honour.
    static var maximum: Float { AVSpeechUtterance.maximumSpeechRate }

    /// `normal` scaled by `multiple`, clamped to the observed bounds.
    ///
    /// The clamp is the point. A rate outside the supported range is not an
    /// error and not clamped for you — it is *silently ignored*, which is the
    /// same class of bug as setting `rate` after `speak()`.
    ///
    /// - Parameter multiple: 1.0 is normal speed, 0.5 is half, 2.0 is double.
    static func scaled(_ multiple: Double) -> Float {
        let target = normal * Float(multiple)
        return min(max(target, minimum), maximum)
    }

    /// The slowest rate a *synthesizer* will honour.
    ///
    /// Use this for a `SpeechPlaying` utterance that should be slow. On real
    /// devices this is `0.0`, which is why it is a weak floor and why a clip
    /// that needs to be scrubbed or backgrounded is rendered to a file instead
    /// — see ``SpeechFileRenderer``.
    static var slowest: Float { minimum }

    /// The fastest rate the app will ask for, as a *multiple* of normal.
    ///
    /// Capped at double rather than pushed to ``maximum``: the upper bound is
    /// fast enough to be unintelligible, and a speed control nobody can follow
    /// is not a control. Exposed as a multiple so the ceiling is stated once.
    static let fastestMultiple: Double = 2.0

    /// The persistent speed-control presets, as multiples of normal.
    ///
    /// Symmetric around 1.0 so "one notch slower" and "one notch faster" sound
    /// like the same distance apart, which is what makes the menu learnable.
    /// Stays under ``fastestMultiple`` deliberately, so the menu is never
    /// faster than the app says it will ever be.
    static let speedMultiples: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5]

    /// The label for a speed preset, e.g. `"0.75×"`.
    static func label(forMultiple multiple: Double) -> String {
        "\(multiple.formatted(.number.precision(.fractionLength(0...2))))×"
    }

    // MARK: - Named rates
    //
    // Every call site that asked for a slightly-too-slow voice used to write its
    // own literal, and each one guessed differently: `0.45`, `0.4`, `0.3`. They
    // were all aiming at "slow enough to pick out the words in an example
    // sentence". These are those intents, named once.

    /// Normal speed, for reading a prompt aloud.
    ///
    /// The default for ``SpeechService/speak(_:voiceID:completion:)``; spelled
    /// out here so a call site that wants "normal, but say it explicitly"
    /// does not have to reach past the convenience overload.
    static var normalSpeed: Float { normal }

    /// A deliberately slow read for a model example or dictation target.
    ///
    /// Slower than the `0.75` speed-menu notch on purpose: the learner is
    /// transcribing this, not skimming it, and the whole point is that each
    /// word is separable.
    static var example: Float { scaled(0.45) }

    /// The slowest the synthesizer will reliably produce.
    ///
    /// For the one case that needs every phoneme: the Hear → Type drill, where
    /// the learner has to reproduce the spelling from sound alone.
    static var drill: Float { scaled(0.3) }

    /// Slow enough to catch a word missed the first time, fast enough that a whole
    /// sentence still sounds like speech.
    ///
    /// The "play slowly" control on a lesson or a topic. Sits between ``example``
    /// and ``normalSpeed``: the learner is listening for comprehension, not
    /// transcribing, so it is quicker than the transcription read.
    static var replay: Float { scaled(0.6) }

    /// The rate slow replay plays a rendered file at, as a fraction of normal.
    ///
    /// This is a **player** rate, not a synthesizer rate, so it is not clamped
    /// to ``minimum``/``maximum`` — those bound what the *synthesizer* honours,
    /// and `minimum` is 0.0 on real devices, so they say nothing useful here.
    /// `AVAudioPlayer` with `enableRate` set accepts roughly `0.25`–`3.0`.
    ///
    /// `0.3` sits just inside that floor: slow enough to resolve individual
    /// phonemes, and still recognisably speech rather than a pitch-shifted
    /// artefact. Below the floor the rate is *ignored* and the learner hears
    /// normal speed from a button labelled "slow" — the same silent-failure
    /// shape as an out-of-range `AVSpeechUtterance.rate`, which is why the
    /// value is stated against `AVAudioPlayer`'s range and not the speech one.
    static let slowestFraction: Float = 0.3
}
