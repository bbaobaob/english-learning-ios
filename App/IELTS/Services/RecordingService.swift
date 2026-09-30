import AVFoundation
import Foundation
import Observation
import UIKit

/// Records one take and plays it back. Nothing is written to Documents and nothing
/// survives the session — the file lives in `tmp` and is deleted when this object goes away.
///
/// Microphone permission is requested on the first explicit record tap, never on screen appear.
@MainActor
@Observable
final class RecordingService {
    enum State: Equatable {
        case idle
        case requestingPermission
        case denied
        case recording
        case recorded
        case playing
    }

    private(set) var state: State = .idle
    /// Seconds spent on the current take.
    private(set) var elapsed: Int = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var levelSamples: [Double] = []

    /// Whether we can even ask — used to pick the explanatory copy.
    var canRequest: Bool { AVAudioApplication.shared.recordPermission == .undetermined }

    init() {}

    deinit {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Recording

    func toggleRecording() {
        switch state {
        case .recording: stopRecording()
        case .playing: stopPlayback()
        case .denied: break
        default: startRecording()
        }
    }

    private func startRecording() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: beginCapture()
        case .denied:
            state = .denied
        case .undetermined:
            state = .requestingPermission
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted { self.beginCapture() } else { self.state = .denied }
                }
            }
        @unknown default:
            state = .denied
        }
    }

    private func beginCapture() {
        stopPlayback()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            state = .denied
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ielts-take-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.delegate = self
            newRecorder.isMeteringEnabled = true
            guard newRecorder.record() else {
                state = .denied
                return
            }
            recorder = newRecorder
            fileURL = url
            elapsed = 0
            levelSamples = []
            state = .recording
            startMetering()
        } catch {
            state = .denied
        }
    }

    func stopRecording() {
        tickTask?.cancel()
        tickTask = nil
        recorder?.stop()
        recorder = nil
        if let fileURL, player == nil {
            player = try? AVAudioPlayer(contentsOf: fileURL)
        }
        if state == .recording { state = .recorded }
        // Release the mic; the session may stay active for playback only.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Where to send the user when permission is off. Never a dead button.
    var settingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    // MARK: - Playback

    var canPlay: Bool { state == .recorded }

    func togglePlayback() {
        state == .playing ? stopPlayback() : play()
    }

    private func play() {
        guard let fileURL else { return }
        if player == nil { player = try? AVAudioPlayer(contentsOf: fileURL) }
        guard let player else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            player.prepareToPlay()
            if player.play() {
                state = .playing
                startMetering()
            }
        } catch {
            state = .recorded
        }
    }

    func stopPlayback() {
        tickTask?.cancel()
        tickTask = nil
        player?.stop()
        if state == .playing { state = .recorded }
    }

    /// Throws away the take. Wired to the "delete" affordance in the recording bar.
    func discard() {
        stopPlayback()
        try? FileManager.default.removeItem(at: fileURL)
        fileURL = nil
        player = nil
        recorder = nil
        elapsed = 0
        levelSamples = []
        state = .idle
    }

    // MARK: - Metering

    private func startMetering() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self else { return }
                self.sampleLevel()
            }
        }
    }

    private func sampleLevel() {
        switch state {
        case .recording:
            recorder?.updateMeters()
            let power = recorder?.averagePower(forChannel: 0) ?? -160
            elapsed += 1
            appendLevel(normalized(power))
        case .playing:
            elapsed = 0
            player?.updateMeters()
            let power = player?.averagePower(forChannel: 0) ?? -160
            appendLevel(normalized(power))
            if !(player?.isPlaying ?? false) { state = .recorded }
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

    /// Recent loudness, newest last. Drawn as a small waveform.
    var waveform: [Double] { Array(levelSamples.suffix(48)) }
}

extension RecordingService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        Task { @MainActor in
            self.tickTask?.cancel()
            self.tickTask = nil
            if flag { self.state = .recorded } else { self.state = .idle }
        }
    }
}