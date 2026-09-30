import SwiftUI
import AVFoundation

// MARK: - AudioLevelProviding
//
// The honesty seam.
//
// A waveform that animates when nothing is playing is a lie: it tells a learner
// listening to a dictation clip that there is audio activity when there is
// none, and it looks like a bug on a device where the session is muted. So the
// level is a *protocol* rather than a closure the view invents, and the view
// draws a flat baseline when no provider supplies one.
//
// Three real sources exist in this app today, in decreasing order of honesty:
//
//   1. **A rendered file, metered.** `AVAudioPlayer` reports
//      `averagePower(forChannel:)` and `peakPower(forChannel:)` in dBFS. This is
//      true metering of audio the user is actually hearing. Wire it up with
//      ``MeteredPlayerLevels``, which polls on the main actor and converts dBFS
//      to `0...1`.
//   2. **A recording, metered.** `AVAudioRecorder.isMeteringEnabled` +
//      `averagePower(forChannel:)` gives the same thing for a speaking take.
//      `RecordingService` in `App/Practice/Services` does *not* enable metering
//      today — see the wiring note on ``LiveWaveform``.
//   3. **TTS.** `AVSpeechSynthesizer` publishes no level at all. There is no
//      honest value to show while speech is playing. Rather than inventing a
//      wobble, the view treats "speaking" as **activity without level**: it
//      animates the baseline subtly and says so, and it is documented as
//      unknown rather than reported as zero.

/// Something that can report a real audio level in `0...1`.
@MainActor
protocol AudioLevelProviding: AnyObject {
    /// The current level, `0...1`, or `nil` when no level is genuinely known.
    ///
    /// `nil` is a meaningful and load-bearing value: it means "playing, but I
    /// cannot measure this". The waveform distinguishes it from `0` (playing,
    /// silent) and shows an explicit baseline rather than a fake bar.
    var currentLevel: Double? { get }
}

// MARK: - MeteredPlayerLevels
//
// The real implementation for a rendered file.

/// Polls an `AVAudioPlayer`'s output meter and publishes a `0...1` level.
///
/// Why a wrapper rather than reading the player directly in the view:
/// `averagePower(forChannel:)` requires `isMeteringEnabled`, and enabling it
/// has to happen once on the audio thread's owner, not on every body
/// evaluation. This type owns that decision and owns the poll interval.
@MainActor
final class MeteredPlayerLevels: ObservableObject, AudioLevelProviding {

    /// The level, `0...1`, or `nil` when there is nothing to report.
    @Published private(set) var currentLevel: Double?

    private weak var player: AVAudioPlayer?
    private var poller: Task<Void, Never>?

    /// dBFS floor. `AVAudioPlayer` reports silence at `-160` dB, so anything
    /// below this is treated as "no signal" rather than as a very quiet signal.
    private let silenceFloor: Double = -55

    /// Seconds between polls. `0.05` is 20 Hz — faster than a bar chart can show,
    /// and within what `AVAudioPlayer`'s meter supports.
    private let interval: Double

    /// - Parameters:
    ///   - player: The player to meter. Held weakly — this type must not keep
    ///     audio alive after the player is gone.
    ///   - interval: Seconds between polls, floored at `0.02`.
    init(player: AVAudioPlayer, interval: Double = 0.05) {
        self.player = player
        self.interval = max(0.02, interval)
        player.isMeteringEnabled = true
        start()
    }

    /// Starts polling. Idempotent.
    ///
    /// The poll is a cancellable `Task`, not a `Timer`, so it is torn down with
    /// the object and cannot survive the screen — and `MeteredPlayerLevels`
    /// should be created and released alongside the player.
    private func start() {
        guard poller == nil else { return }
        poller = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.sample()
                // Sleeping in slices keeps the task cancellable mid-wait, which a
                // `Timer.sleep` would not.
                try? await Task.sleep(for: .seconds(self?.interval ?? 0.05))
            }
        }
    }

    private func sample() {
        guard let player else {
            currentLevel = nil
            return
        }
        player.updateMeters()
        let decibels = Double(player.averagePower(forChannel: 0))
        guard decibels.isFinite else {
            currentLevel = nil
            return
        }
        guard decibels > silenceFloor else {
            // Genuinely silent. `0` is an honest answer here, unlike "speaking
            // with no meter", which is `nil`.
            currentLevel = 0
            return
        }
        // Map the useful part of the dB scale onto 0...1. The floor is the quiet
        // end of speech, the ceiling is clipping, so the curve spends most of
        // its range where a voice actually lives.
        let normalized = (decibels - silenceFloor) / -silenceFloor
        currentLevel = min(max(normalized, 0), 1)
    }

    deinit {
        poller?.cancel()
    }
}