import AVFoundation
import Foundation
import Observation
import UIKit

/// Records one speaking take and plays it back.
///
/// Deliberately forgetful: the recording lives in `FileManager.temporaryDirectory`
/// and is deleted on `discard()` and on `deinit`. Nothing about a learner's voice
/// is persisted, and the app ships no microphone-retention affordance.
///
/// **One service for the whole app.** The Practice and IELTS lanes each wrote
/// their own; two `final class RecordingService`s in one target is a
/// redeclaration error, and the two versions had drifted into different
/// vocabularies. This is the union of both, with one state machine:
///
/// * ``permission`` is the only place iOS authorisation is read, and the only
///   thing that decides whether a tap asks or records.
/// * ``state`` is the recording lifecycle, and every flag the views read
///   (``isRecording``, ``hasTake``, ``canPlay``, ``isPlaying``) is derived from
///   it. There is no second copy of the truth to fall out of sync.
/// * ``waveform`` is the recent loudness envelope, for the meter under the bar.
///
/// Microphone permission is requested from ``requestPermission()``, never from an
/// initializer or a `task`, because iOS only shows the prompt on a user action.
@MainActor
@Observable
final class RecordingService {

    // MARK: - Authorisation

    /// What iOS currently allows.
    enum Permission: Equatable {
        /// Not asked yet; the UI offers a button that asks.
        case undetermined
        /// Recording is allowed.
        case granted
        /// The learner refused, or a parental restriction blocks it.
        case denied
    }

    /// The current microphone authorisation, as last observed by this service.
    ///
    /// Written by ``requestPermission()`` and by ``startRecording()``. Views
    /// read it to decide whether to offer "turn on the microphone" copy; they
    /// never infer it from ``state``.
    private(set) var permission: Permission = .undetermined

    /// The permission iOS reports right now, without prompting or mutating.
    ///
    /// Used by a view that appears after the service was created but before the
    /// learner tapped anything, so it shows the right copy on first run.
    var observedPermission: Permission { Self.currentPermission }

    /// The permission the app would report right now, without prompting.
    static var currentPermission: Permission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        case .undetermined: .undetermined
        @unknown default: .undetermined
        }
    }

    /// Asks iOS for microphone access. Must be called from a user action.
    func requestPermission() async {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        permission = granted ? .granted : .denied
        if granted {
            errorMessage = nil
        } else {
            state = .denied
            errorMessage = "English Learning needs the microphone to record your speaking take. "
                + "Nothing is saved — the recording is deleted as soon as you leave this screen."
        }
    }

    // MARK: - State

    /// The recording lifecycle. The single source of truth.
    enum State: Equatable {
        case idle
        case requestingPermission
        case denied
        case recording
        case recorded
        case playing
    }

    private(set) var state: State = .idle

    /// Seconds captured in the current or most recent take.
    private(set) var elapsed: TimeInterval = 0

    /// A human-readable failure to show in an `ErrorBanner`, `nil` when healthy.
    private(set) var errorMessage: String?

    // Derived flags. Each is one equality test against ``state`` rather than a
    // second stored value, so the two can never disagree.

    /// Whether a take is being captured right now.
    var isRecording: Bool { state == .recording }

    /// Whether the captured take is being played back.
    var isPlaying: Bool { state == .playing }

    /// Whether a take exists and can be played, re-recorded, or deleted.
    var hasTake: Bool { state == .recorded || state == .playing }

    /// Whether there is something to play back.
    var canPlay: Bool { hasTake }

    /// Whole seconds on the clock. The views format this, not the raw double.
    var elapsedSeconds: Int { Int(elapsed.rounded(.down)) }

    // MARK: - Private state

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?
    private var takeURL: URL?
    private var levelSamples: [Double] = []

    /// Recent loudness, newest last. Drawn as a small waveform.
    var waveform: [Double] { Array(levelSamples.suffix(48)) }

    /// Where to send the user when permission is off. Never a dead button.
    var settingsURL: URL? { URL(string: UIApplication.openSettingsURLString) }

    init() {}

    deinit {
        try? FileManager.default.removeItem(at: takeURL)
    }


    // MARK: - Recording

    /// Starts a take, replacing any previous one. Asks for permission first if
    /// that has not happened yet, because iOS only prompts on a user action.
    ///
    /// - Returns: `false` when permission is missing or the recorder refused to
    ///   start; the reason is in ``errorMessage`` either way.
    @discardableResult
    func startRecording() -> Bool {
        switch permission {
        case .undetermined:
            state = .requestingPermission
            Task { await requestPermission() }
            return false
        case .denied:
            state = .denied
            errorMessage = "Recording needs microphone access. Turn it on to try your answer aloud."
            return false
        case .granted:
            break
        }

        stopPlayback()
        discard()
        return beginCapture()
    }

    private func beginCapture() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            state = .denied
            errorMessage = "The microphone could not be opened: \(error.localizedDescription)"
            return false
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("take-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.isMeteringEnabled = true
            guard newRecorder.record() else {
                errorMessage = "The recorder would not start. Close any other app that may be using the microphone."
                return false
            }
            recorder = newRecorder
            takeURL = url
            elapsed = 0
            levelSamples = []
            errorMessage = nil
            state = .recording
            startTicker()
            return true
        } catch {
            errorMessage = "Recording could not start: \(error.localizedDescription)"
            return false
        }
    }

    /// Stops the take and keeps it for playback.
    func stopRecording() {
        guard let recorder, isRecording else { return }
        stopTicker()
        recorder.stop()
        self.recorder = nil
        hasTakeOnDisk ? (state = .recorded) : (state = .idle)
        // Release the mic; the session may stay active for playback only.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// One button that records, stops, or stops playback, depending on state.
    ///
    /// The single affordance the IELTS recording bar uses, where the same button
    /// is "Record", "Stop" and "Asking…" depending on where the take is.
    func toggleRecording() {
        switch state {
        case .recording: stopRecording()
        case .playing: stopPlayback()
        case .denied, .requestingPermission: break
        default: startRecording()
        }
    }

    private var hasTakeOnDisk: Bool {
        takeURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    // MARK: - Playback

    /// Plays the captured take from the beginning. No-op when there is nothing to play.
    func playTake() {
        guard let takeURL, hasTake else { return }
        if player == nil {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true)
                player = try AVAudioPlayer(contentsOf: takeURL)
            } catch {
                errorMessage = "That take could not be played back: \(error.localizedDescription)"
                return
            }
        }
        guard let player else { return }
        player.play()
        state = .playing
        errorMessage = nil
        // The ticker watches `player.isPlaying`, because playback ends on its
        // own and nothing calls back in to update `state`.
        startTicker()
    }

    /// Stops playback, leaving the take on disk.
    func stopPlayback() {
        stopTicker()
        player?.stop()
        player = nil
        if state == .playing { state = .recorded }
    }

    /// Plays the take if there is one, otherwise stops it.
    func togglePlayback() {
        isPlaying ? stopPlayback() : playTake()
    }

    /// Throws the take away. Called before a re-record and when leaving the screen.
    func discard() {
        stopPlayback()
        stopTicker()
        recorder?.stop()
        recorder = nil
        elapsed = 0
        levelSamples = []
        if let takeURL {
            try? FileManager.default.removeItem(at: takeURL)
        }
        takeURL = nil
        if state != .denied { state = .idle }
    }

    /// Clears the current failure message.
    func clearError() {
        errorMessage = nil
    }

    // MARK: - Metering

    /// The most recent sampled level, `0...1`, or `nil` when nothing is running.
    ///
    /// Part of ``AudioLevelProviding`` so `LiveWaveform` can be driven by what is
    /// genuinely measured. The recorder's output meter is the source — this is not
    /// a synthesised level dressed up as one, which is the whole point of that
    /// protocol existing.
    var currentLevel: Double? {
        guard state == .recording || state == .playing else { return nil }
        return levelSamples.last
    }

    private func startTicker() {
        stopTicker()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func tick() {
        switch state {
        case .recording:
            recorder?.updateMeters()
            elapsed = recorder?.currentTime ?? elapsed
            appendLevel(normalized(recorder?.averagePower(forChannel: 0) ?? -160))
        case .playing:
            player?.updateMeters()
            elapsed = player?.currentTime ?? 0
            appendLevel(normalized(player?.averagePower(forChannel: 0) ?? -160))
            if !(player?.isPlaying ?? false) {
                // Playback finished on its own. Drop back to `recorded` so the
                // play button offers to play again rather than a dead stop.
                stopPlayback()
            }
        default:
            break
        }
    }

    private func appendLevel(_ value: Double) {
        levelSamples.append(value)
        if levelSamples.count > 60 { levelSamples.removeFirst() }
    }

    private func normalized(_ decibels: Float) -> Double {
        // -60 dB is effectively silence for speech; map that to zero.
        let clamped = max(Double(decibels), -60) + 60
        return min(max(clamped / 60, 0), 1)
    }
}
// The level the recorder actually measured, exposed for `LiveWaveform`. See
// ``RecordingService/currentLevel``.
extension RecordingService: AudioLevelProviding {}
