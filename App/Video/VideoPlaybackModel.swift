import SwiftUI
import AVKit
import Observation
import EnglishCore

/// The playback state behind ``VideoLessonView``.
///
/// Separate from the view because `AVPlayer` is a reference type that must
/// survive body re-evaluations, and because a periodic time observer has to be
/// installed exactly once and torn down exactly once. Holding either in a
/// `@State` inside the view risks a leaked observer every time SwiftUI
/// re-creates the view's storage.
///
/// The view owns an instance; the caller owns nothing. Position flows in as a
/// parameter and back out through the `bookmark` closure, which keeps
/// persistence in `ProgressStore` and out of the player.
@MainActor
@Observable
final class VideoPlaybackModel {

    // MARK: - Published state

    /// The player. Nil until a URL is resolved.
    private(set) var player: AVPlayer?

    /// Whether playback is advancing.
    private(set) var isPlaying: Bool = false

    /// Current position in seconds.
    private(set) var currentTime: Double = 0

    /// Total length in seconds, from the player or from the content.
    private(set) var duration: Double = 0

    /// Playback rate multiplier.
    var rate: Float = 1.0 {
        didSet {
            guard rate != oldValue else { return }
            applyRate()
        }
    }

    /// A load or buffering failure.
    private(set) var errorMessage: String?

    /// The `SubtitleCue` covering `currentTime`, or nil between cues.
    ///
    /// Computed rather than stored, so it is always consistent with the time
    /// that produced it and there is no second source of truth to fall behind.
    var activeCue: SubtitleCue? {
        subtitles.first { currentTime >= $0.start && currentTime < $0.end }
    }

    /// The cues this player was given, set once when the clip is loaded.
    @ObservationIgnored
    private var subtitles: [SubtitleCue] = []

    @ObservationIgnored
    private var timeObserver: Any?
    @ObservationIgnored
    private var endObserver: NSObjectProtocol?

    /// Called roughly every five seconds while playing, and on disappear, so
    /// the caller can persist the position.
    @ObservationIgnored
    var onPeriodicPosition: ((Double) -> Void)?

    init(clip: VideoClip) {
        self.subtitles = clip.subtitles.sorted { $0.start < $1.start }

        // The content's declared length is used until the player reports its
        // own, so the scrubber has a real range immediately instead of
        // snapping into place once the file is buffered.
        self.duration = clip.durationSeconds ?? 0

        guard let url = clip.source.url else {
            // `.none` is a legal, complete state, not a failure: the view
            // renders a calm placeholder and the lesson continues.
            return
        }
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        self.player = player
        installObservers(on: player)
    }

    deinit {
        // `timeObserver` and `endObserver` are the only things that outlive a
        // deinit; the player itself is released with the model.
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    // MARK: - Transport

    /// Starts or resumes.
    func play() {
        guard let player else { return }
        player.playImmediately(atRate: rate)
        isPlaying = true
    }

    /// Pauses.
    func pause() {
        player?.pause()
        isPlaying = false
    }

    /// Play/pause, for the single main transport button.
    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    /// Jumps to `seconds`, clamped to the clip.
    ///
    /// - Parameter seconds: The target position. A seek while the player has
    ///   not finished loading is dropped, because `AVPlayer` silently ignores
    ///   one and the scrubber would snap back with no explanation.
    func seek(to seconds: Double) {
        guard let player else { return }
        let target = min(max(seconds, 0), max(duration, 0))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        currentTime = target
    }

    /// Nudges the position by `seconds`, used by the 15-second skips.
    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    private func applyRate() {
        guard isPlaying else { return }
        player?.rate = rate
    }

    // MARK: - Observers

    private func installObservers(on player: AVPlayer) {
        // 0.5s: fine enough for a subtitle to feel synchronised, coarse enough
        // that a 4-minute video is not re-rendering 480 times.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = time.seconds
                guard seconds.isFinite else { return }
                self.currentTime = seconds
                if let total = self.player?.currentItem?.duration.seconds, total.isFinite, total > 0 {
                    self.duration = total
                }
                // Every tenth tick is five seconds, which is the bookmark
                // cadence. Persisting on every half second would write to
                // SwiftData far faster than the position can meaningfully change.
                if Int(seconds * 2) % 10 == 0 {
                    self.onPeriodicPosition?(seconds)
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = false
                self.currentTime = self.duration
            }
        }
    }
}
