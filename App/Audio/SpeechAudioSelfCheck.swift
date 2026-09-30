import Foundation
import AVFoundation

/// A runnable check for the audio contracts that are easy to get subtly wrong.
///
/// The two rules this verifies are both silent when broken, which is exactly
/// what makes them worth a test:
///
/// * **Every rate the app requests is inside the range the system actually
///   reports.** A rate outside it is not clamped by the framework, it is
///   *ignored* — so a "slow replay" button that asks for too little plays at
///   normal speed and nothing anywhere reports a problem.
/// * **The cache key distinguishes `(text, rate, voice)`.** A collision means a
///   learner hears a sentence at the speed of a different one, which is a bug
///   that only shows up on a second visit to a lesson.
///
/// Run it from a debug menu, a unit test, or the simulator console:
///
/// ```swift
/// SpeechAudioSelfCheck.run()
/// ```
enum SpeechAudioSelfCheck {

    /// One assertion result.
    struct Result {
        let name: String
        let passed: Bool
        let detail: String
    }

    /// Runs every check and returns the results.
    @discardableResult
    static func run() -> [Result] {
        var results: [Result] = []
        results.append(checkRatesAreInRange())
        results.append(checkSlowestIsSlowerThanNormal())
        results.append(checkSlowReplayIsSlowerAndPlayable())
        results.append(checkSpeedPresetsAreOrdered())
        results.append(checkCacheKeyVariesByRate())
        results.append(checkCacheKeyVariesByText())
        results.append(checkCacheKeyVariesByVoice())
        results.append(checkCacheKeyIsStable())
        results.append(checkCacheKeySurvivesPathSeparators())
        return results
    }

    /// Runs every check and traps on the first failure.
    ///
    /// For a test target: the whole point is that these cannot be observed from
    /// the UI, so a green run here is the only evidence they hold.
    static func assertAll() {
        for result in run() {
            assert(result.passed, "SpeechAudioSelfCheck: \(result.name) — \(result.detail)")
        }
    }

    // MARK: - Checks

    /// Every rate reachable from the app's own helpers is inside the range the
    /// system reports right now.
    private static func checkRatesAreInRange() -> Result {
        let name = "every requested rate is within the system's range"
        let low = SpeechRate.minimum
        let high = SpeechRate.maximum

        // `slowestFraction` is deliberately *outside* this range: it is a player
        // rate for a rendered file, not a synthesizer rate. It is excluded here
        // deliberately, and asserted separately in the UI path.
        var offenders: [String] = []
        for multiple in [0.1, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 4.0, 10.0] {
            let rate = SpeechRate.scaled(multiple)
            if rate < low || rate > high {
                offenders.append("\(multiple)× → \(rate)")
            }
        }
        for rate in [SpeechRate.normal, SpeechRate.minimum, SpeechRate.maximum, SpeechRate.slowest] {
            if rate < low || rate > high {
                offenders.append("constant \(rate)")
            }
        }

        return Result(
            name: name,
            passed: offenders.isEmpty,
            detail: offenders.isEmpty
                ? "scaled(_:) clamps to \(low)…\(high)"
                : "out of range: \(offenders.joined(separator: ", "))"
        )
    }

    /// "Slow" has to actually be slower, or the button is a lie.
    private static func checkSlowestIsSlowerThanNormal() -> Result {
        let name = "the slowest synthesizer rate is slower than normal"
        let passed = SpeechRate.slowest < SpeechRate.normal
        return Result(
            name: name,
            passed: passed,
            detail: "slowest \(SpeechRate.slowest) vs normal \(SpeechRate.normal)"
        )
    }

    /// The slow-replay rate must be slower than normal, and inside the range
    /// `AVAudioPlayer` honours.
    ///
    /// Note what this does *not* assert: that it is below the synthesizer's
    /// floor. `AVSpeechUtteranceMinimumSpeechRate` is 0.0 on real devices, so
    /// there is no rate a file can play at that a synthesizer cannot also
    /// produce. The reason speech clips are rendered is not that a file can go
    /// slower than speech — it is that a file can be *scrubbed, paused, and
    /// backgrounded at all*, which an utterance cannot.
    private static func checkSlowReplayIsSlowerAndPlayable() -> Result {
        let name = "slow replay is slower than normal and within the player's range"
        let slower = SpeechRate.slowestFraction < SpeechRate.normal
        // `AVAudioPlayer` documents roughly 0.25–3.0 with `enableRate`. 0.3 sits
        // just inside the floor; below it the rate is ignored and the learner
        // hears normal speed from a button labelled "slow".
        let playable = SpeechRate.slowestFraction >= 0.25
        return Result(
            name: name,
            passed: slower && playable,
            detail: "slow replay \(SpeechRate.slowestFraction) vs normal \(SpeechRate.normal); "
                + "slower: \(slower), above player floor 0.25: \(playable)"
        )
    }

    /// The speed menu must run slow → fast, include normal speed, and stay
    /// inside the ceiling the app documents.
    private static func checkSpeedPresetsAreOrdered() -> Result {
        let name = "speed presets are ordered, include normal, and respect the ceiling"
        let presets = SpeechRate.speedMultiples
        let ascending = zip(presets, presets.dropFirst()).allSatisfy { $0 < $1 }
        let hasNormal = presets.contains(1.0)
        let withinCeiling = presets.allSatisfy { $0 <= SpeechRate.fastestMultiple }
        return Result(
            name: name,
            passed: ascending && hasNormal && withinCeiling,
            detail: "\(presets) ascending: \(ascending), has 1.0: \(hasNormal), "
                + "within \(SpeechRate.fastestMultiple)×: \(withinCeiling)"
        )
    }

    private static func checkCacheKeyVariesByRate() -> Result {
        let name = "cache key differs when the rate differs"
        let a = SpeechFileRenderer.Key(text: "The boy is playing football.", rate: SpeechRate.normal, voiceID: nil)
        let b = SpeechFileRenderer.Key(
            text: "The boy is playing football.",
            rate: SpeechRate.scaled(0.5),
            voiceID: nil
        )
        return Result(
            name: name,
            passed: a != b && fileName(for: a) != fileName(for: b),
            detail: "\(a.rate) vs \(b.rate)"
        )
    }

    private static func checkCacheKeyVariesByText() -> Result {
        let name = "cache key differs when the text differs"
        let a = SpeechFileRenderer.Key(text: "The boy is playing football.", rate: SpeechRate.normal, voiceID: nil)
        let b = SpeechFileRenderer.Key(text: "The boy is play football.", rate: SpeechRate.normal, voiceID: nil)
        return Result(name: name, passed: a != b, detail: "one word differs")
    }

    private static func checkCacheKeyVariesByVoice() -> Result {
        let name = "cache key differs when the voice differs"
        let a = SpeechFileRenderer.Key(text: "Hello.", rate: SpeechRate.normal, voiceID: "com.apple.voice.compact.en-GB.Daniel")
        let b = SpeechFileRenderer.Key(text: "Hello.", rate: SpeechRate.normal, voiceID: "com.apple.voice.compact.en-US.Alex")
        return Result(name: name, passed: a != b, detail: "two installed-voice ids")
    }

    /// The same request must produce the same file, or nothing is ever a cache
    /// hit and every visit re-renders.
    private static func checkCacheKeyIsStable() -> Result {
        let name = "cache key is stable for the same request"
        let a = SpeechFileRenderer.Key(text: "Hello.", rate: SpeechRate.normal, voiceID: "com.apple.voice.en-US.Alex")
        let b = SpeechFileRenderer.Key(text: "Hello.", rate: SpeechRate.normal, voiceID: "com.apple.voice.en-US.Alex")
        return Result(name: name, passed: a == b, detail: "identical inputs, identical key")
    }

    /// Sentences contain apostrophes and slashes; the filename must not.
    private static func checkCacheKeySurvivesPathSeparators() -> Result {
        let name = "cache filename is filesystem-safe for awkward text"
        let awkward = [
            "He's going / she's not.",
            "../../escape",
            "A very long sentence that keeps going and going and going and going and going and going and going and going",
            "emoji 🎧 and accents éàü",
            "",
        ]
        for text in awkward {
            let key = SpeechFileRenderer.Key(text: text, rate: SpeechRate.normal, voiceID: nil)
            let name = fileName(for: key)
            let safe = name.count == 64
                && name.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isLowercase) }
            guard !safe else { continue }
            return Result(name: name, passed: false, detail: "unsafe filename for \(text.prefix(20)): \(name)")
        }
        return Result(name: name, passed: true, detail: "\(awkward.count) awkward inputs produced 64-char hex names")
    }

    // MARK: - Helpers

    /// The same naming the renderer uses, so the check tests the real thing
    /// rather than a copy of it.
    private static func fileName(for key: SpeechFileRenderer.Key) -> String {
        SpeechFileRenderer.fileNameForTesting(key)
    }
}
