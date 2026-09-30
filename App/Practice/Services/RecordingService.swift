import Foundation
import Observation
import AVFoundation

/// Records one speaking take to a temporary file and plays it back.
///
/// Deliberately forgetful: the recording lives in `FileManager.temporaryDirectory`
/// and is deleted on `discard()` and on `deinit`. Nothing about a learner's voice
/// is persisted, and the app ships no microphone-retention affordance.
///
/// Microphone permission is requested from `requestPermission()`, never from an
/// initializer or a `task`, because iOS only shows the prompt on a user action.
///
/// ponytail: one take at a time and no waveform metering. If speaking practice ever
/// needs live levels, add a metering timer here rather than in the view.
@MainActor
@Observable
final class RecordingService {

    /// What iOS currently allows.
    enum Permission: Equatable {
        /// Not asked yet; the UI offers a button that asks.
        case undetermined
        /// Recording is allowed.
        case granted
        /// The learner refused, or a parental restriction blocks it.
        case denied
    }

    /// The current microphone authorisation.
    private(set) var permission: Permission = .undetermined

    /// Whether a take is being captured right now.
    private(set) var isRecording = false

    /// Whether the captured take is being played back.
    private(set) var isPlaying = false

    /// Seconds captured in the current or most recent take.
    private(set) var elapsed: TimeInterval = 0

    /// Whether a take exists and can be played or re-recorded.
    private(set) var hasTake = false

    /// A human-readable failure to show in an `ErrorBanner`, `nil` when healthy.
    private(set) var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var ticker: Timer?
    private var takeURL: URL?

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
        if !granted {
            errorMessage = "English Learning needs the microphone to record your speaking take. "
                + "Nothing is saved — the recording is deleted as soon as you leave this screen."
        }
    }

    /// Starts a take, replacing any previous one.
    ///
    /// - Returns: `false` when permission is missing or the recorder refused to
    ///   start; the reason is in ``errorMessage`` either way.
    @discardableResult
    func startRecording() -> Bool {
        stopPlayback()
        discard()
        guard permission == .granted else {
            errorMessage = "Recording needs microphone access. Turn it on to try your answer aloud."
            return false
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("practice-take-\(UUID().uuidString)")
                .appendingPathExtension("m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            guard recorder.record() else {
                errorMessage = "The recorder would not start. Close any other app that may be using the microphone."
                return false
            }

            self.recorder = recorder
            takeURL = url
            elapsed = 0
            hasTake = false
            isRecording = true
            errorMessage = nil
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
        recorder.stop()
        self.recorder = nil
        isRecording = false
        stopTicker()
        hasTake = takeURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// Plays the captured take from the beginning. No-op when there is nothing to play.
    func playTake() {
        guard let takeURL, hasTake else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: takeURL)
            player.prepareToPlay()
            player.play()
            self.player = player
            isPlaying = true
            errorMessage = nil
        } catch {
            errorMessage = "That take could not be played back: \(error.localizedDescription)"
        }
    }

    /// Stops playback, leaving the take on disk.
    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    /// Throws the take away. Called before a re-record and when leaving the screen.
    func discard() {
        stopPlayback()
        stopTicker()
        recorder?.stop()
        recorder = nil
        isRecording = false
        elapsed = 0
        hasTake = false
        if let takeURL {
            try? FileManager.default.removeItem(at: takeURL)
        }
        takeURL = nil
    }

    /// Clears the current failure message.
    func clearError() {
        errorMessage = nil
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                self.elapsed = recorder.currentTime
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
