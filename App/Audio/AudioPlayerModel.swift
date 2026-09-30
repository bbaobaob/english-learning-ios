import Foundation
import AVFoundation
import MediaPlayer
import Observation

/// Plays one `AudioClip` at a time, whichever of the three kinds it is.
///
/// Why one model and not three: `AudioClip.kind` is a content-authoring
/// decision, and the doc is explicit that `file`/`remote` exist so recorded
/// audio can be dropped in later *without touching UI*. The UI therefore
/// never branches on `kind` — it asks the model to `play(clip:)` and then
/// renders whatever the model says is happening. That is the whole point.
///
/// This type also implements ``SpeechPlaying``, so a screen that only needs a
/// word spoken (an example sentence, a vocabulary entry) can use the same
/// object it already has instead of holding a second synthesizer.
///
/// Everything is `@MainActor` because `AVPlayer` and `AVSpeechSynthesizer` are
/// main-actor-isolated, and `@Observable` because a player updates constantly
/// and every millisecond of `elapsed` should not trigger a view re-evaluation
/// on its own — the views read `elapsed` where a scrubber wants it.
@MainActor
@Observable
public final class AudioPlayerModel {

    // MARK: - Published state

    /// The clip currently loaded, if any.
    private(set) var clip: AudioClip?

    /// Whether audio is advancing right now.
    private(set) var isPlaying: Bool = false

    /// Playback position in seconds. For a `speech` clip this is an estimate
    /// derived from the utterance's character count and rate, not a real clock.
    private(set) var elapsed: TimeInterval = 0

    /// Total length in seconds. `0` for a `speech` clip whose length cannot be
    /// known before it is spoken.
    private(set) var duration: TimeInterval = 0

    /// `true` while a file or remote clip is being fetched.
    private(set) var isLoading: Bool = false

    /// A human-readable failure, or `nil`. The player keeps working; the view
    /// decides whether to show this.
    private(set) var errorMessage: String?

    /// Playback rate multiplier. Mapped onto the underlying engine's rate.
    var playbackRate: Float = 1.0 {
        didSet {
            guard playbackRate != oldValue else { return }
            applyRate()
        }
    }

    /// Whether the clip restarts when it ends.
    var isLooping: Bool = false

    /// Whether replays draw from a shuffled order. Meaningful for a set of
    /// clips; for a single clip it changes nothing, which is why the UI only
    /// offers it where there is a set.
    var isShuffled: Bool = false

    /// How many times to play the clip before stopping. `1` means play once.
    /// Clamped to `1...20` — past that it is a loop, not a counter.
    var repeatCount: Int = 1 {
        didSet {
            repeatCount = min(max(repeatCount, 1), 20)
        }
    }

    /// How many of the `repeatCount` plays have finished.
    private(set) var completedPlays: Int = 0

    /// The rate the *slow replay* button uses, as a fraction of the clip's own
    /// rate. Deliberately below the slowest selectable speed: slow replay is
    /// for hearing a single phoneme or a half-finished word, not for working
    /// through a whole sentence.
    let slowRate: Float = 0.45

    // MARK: - Collaborators

    /// Speech is delegated out so one `AVSpeechSynthesizer` serves the whole
    /// app; two synthesizers speaking at once interleave audibly.
    @ObservationIgnored
    private let speech: SpeechService

    @ObservationIgnored
    private var player: AVAudioPlayer?

    /// Drives `elapsed` and detects the end of a clip.
    @ObservationIgnored
    private var ticker: Timer?

    @ObservationIgnored
    private var observers: [NSObjectProtocol] = []

    // MARK: - SpeechPlaying

    /// `true` while the shared synthesizer has an utterance in flight.
    public var isSpeaking: Bool { speech.isSpeaking }

    public init(speech: SpeechService) {
        self.speech = speech
        installNotificationHandlers()
        installRemoteCommands()
    }

    deinit {
        // The timer and the notification tokens are the only two things that
        // outlive a `deinit`; the synthesizer stops itself.
        ticker?.invalidate()
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Playback

    /// Loads `clip` and optionally starts it.
    ///
    /// Loading is idempotent for the clip's identity: calling this again with
    /// the same clip does not restart it, which is what lets a view call it
    /// from `.onAppear` without thinking.
    ///
    /// - Parameters:
    ///   - clip: The clip to play.
    ///   - autoplay: Start playing as soon as it is ready.
    func play(_ clip: AudioClip, autoplay: Bool = true) {
        if self.clip?.id == clip.id, player != nil || isSpeaking {
            if autoplay, !isPlaying { resume() }
            return
        }
        stop()
        self.clip = clip
        completedPlays = 0
        errorMessage = nil
        applyAudioSession()

        switch clip.kind {
        case .speech:
            loadSpeech(clip)
        case .file:
            loadFile(clip)
        case .remote:
            loadRemote(clip)
        }
        if autoplay { resume() }
    }

    /// Stops everything and releases the loaded clip.
    func stop() {
        speech.stop()
        speechCompletion = nil
        player?.stop()
        player = nil
        isPlaying = false
        isLoading = false
        elapsed = 0
        duration = 0
        clearTicker()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Starts or resumes from the current position.
    func resume() {
        guard let clip else { return }
        switch clip.kind {
        case .speech:
            if synthesizer.isSpeaking {
                // Already speaking: restart the sentence rather than ignoring
                // the tap, which is what a learner pressing play twice means.
                speech.speak(clip.text ?? "", rate: scaledSpeechRate, completion: nil)
                isPlaying = true
                return
            }
            isPlaying = true
            speech.speak(
                clip.text ?? "",
                rate: scaledSpeechRate,
                completion: { [weak self] in self?.handleClipFinished() }
            )
        case .file, .remote:
            guard let player else { return }
            player.enableRate = true
            player.play()
            isPlaying = true
            startTicker()
        }
        updateNowPlaying()
    }

    /// Pauses. A paused utterance is stopped, not resumed: `AVSpeechSynthesizer`
    /// cannot resume mid-sentence, so pretending otherwise would silently
    /// restart it.
    func pause() {
        switch clip?.kind {
        case .speech:
            speech.stop()
            isPlaying = false
        case .file, .remote:
            player?.pause()
            isPlaying = false
        case nil:
            return
        }
        clearTicker()
        updateNowPlaying()
    }

    /// Play/pause, the single control the transport bar's main button uses.
    func togglePlayback() {
        isPlaying ? pause() : resume()
    }

    /// Restarts the clip from zero, keeping the current settings.
    func replay() {
        guard clip != nil else { return }
        elapsed = 0
        switch clip?.kind {
        case .speech:
            speech.stop()
            isPlaying = true
            speech.speak(
                clip?.text ?? "",
                rate: scaledSpeechRate,
                completion: { [weak self] in self?.handleClipFinished() }
            )
        case .file, .remote:
            player?.currentTime = 0
            isPlaying = true
            player?.play()
            startTicker()
        }
        updateNowPlaying()
    }

    /// The first-class dictation and alphabet control: the same clip again, at
    /// a much lower rate.
    ///
    /// This is not `playbackRate = 0.5`. The speed control is a study tool the
    /// learner sets once; slow replay is a momentary action that always plays
    /// slowly and always from the start, because the words being listened for
    /// are at the beginning of the sentence.
    func slowReplay() {
        guard let clip else { return }
        stop()
        self.clip = clip
        applyAudioSession()
        switch clip.kind {
        case .speech:
            isPlaying = true
            elapsed = 0
            speech.speak(
                clip.text ?? "",
                rate: clip.speakingRate * slowRate,
                completion: { [weak self] in self?.handleClipFinished() }
            )
        case .file, .remote:
            guard let player else { return }
            player.currentTime = 0
            player.enableRate = true
            player.rate = slowRate
            isPlaying = true
            startTicker()
        }
        updateNowPlaying()
    }

    /// Seeks to `seconds`, clamped to the clip.
    func seek(to seconds: TimeInterval) {
        guard let clip else { return }
        let target = min(max(seconds, 0), max(duration, 0))
        switch clip.kind {
        case .speech:
            // A speech clip has no timeline to scrub, so seeking restarts the
            // utterance. The scrubber is hidden in this case, so this only
            // happens from a keyboard or VoiceOver action.
            elapsed = target
            if isPlaying { replay() }
        case .file, .remote:
            player?.currentTime = target
            elapsed = target
            updateNowPlaying()
        }
    }

    /// Nudges the position by `seconds`, used by the 10-second skip controls.
    func skip(by seconds: TimeInterval) {
        seek(to: elapsed + seconds)
    }

    /// Appends one to the repeat counter, clamped to the legal range.
    func incrementRepeat() {
        repeatCount = min(repeatCount + 1, 20)
    }

    /// Subtracts one from the repeat counter, clamped to the legal range.
    func decrementRepeat() {
        repeatCount = max(repeatCount - 1, 1)
    }

    // MARK: - Loading

    private func loadSpeech(_ clip: AudioClip) {
        guard let text = clip.text, !text.isEmpty else {
            errorMessage = "This clip has no text to speak."
            return
        }
        // `AVSpeechUtterance` has no duration before it is spoken, so the
        // estimate is what the scrubber and the "total" label show. It is an
        // estimate on purpose: a wrong total is better than a spinner.
        duration = estimatedSpeechDuration(text: text, rate: scaledSpeechRate)
        elapsed = 0
        player = nil
    }

    private func loadFile(_ clip: AudioClip) {
        guard let fileName = clip.fileName,
              let url = Bundle.main.url(forResource: fileName, withExtension: nil) ?? fileNameURL(fileName) else {
            errorMessage = "The audio file for this lesson is missing."
            return
        }
        loadPlayer(url: url, clip: clip)
    }

    private func loadRemote(_ clip: AudioClip) {
        guard let url = clip.url else {
            errorMessage = "This lesson has no audio link."
            return
        }
        isLoading = true
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                isLoading = false
                if let error {
                    errorMessage = "Audio could not be downloaded: \(error.localizedDescription)"
                    return
                }
                guard let data else {
                    errorMessage = "Audio could not be downloaded."
                    return
                }
                loadPlayerData(data, clip: clip)
            }
        }.resume()
    }

    /// Bundled clip audio may ship with a `subdirectory` in its name, e.g.
    /// `"audio/a-1.mp3"`. `Bundle.url(forResource:withExtension:)` does not
    /// search subdirectories, so the split is done by hand.
    private func fileNameURL(_ fileName: String) -> URL? {
        let parts = fileName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return Bundle.main.url(forResource: parts[1], withExtension: nil, subdirectory: parts[0])
    }

    private func loadPlayer(url: URL, clip: AudioClip) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            duration = player.duration
            elapsed = 0
        } catch {
            errorMessage = "This audio file could not be opened."
            player = nil
        }
    }

    private func loadPlayerData(_ data: Data, clip: AudioClip) {
        do {
            let player = try AVAudioPlayer(data: data)
            player.enableRate = true
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            duration = player.duration
            elapsed = 0
        } catch {
            errorMessage = "This audio file could not be opened."
            player = nil
        }
    }

    // MARK: - Session and interruptions

    /// `.playback` so audio continues with the screen off, `.spokenAudio` so
    /// the system applies spoken-audio EQ and ducks other apps correctly.
    private func applyAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        } catch {
            // A failed session activation is not fatal: `AVAudioPlayer` still
            // plays through the speaker, it just will not survive the screen
            // locking. Surfacing a hard error for that would be worse than the
            // limitation.
            errorMessage = nil
        }
    }

    private func installNotificationHandlers() {
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in self?.handleInterruption(note) }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleRouteChange() }
        })

        // A speech clip that ends is not reported by the synthesizer's delegate
        // through this model, so the completion closure above handles it.
    }

    private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        switch type {
        case .began:
            // The system paused us (a call, Siri). Mirror that so the
            // transport button does not claim to be playing.
            if isPlaying { pause() }
        case .ended:
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map {
                AVAudioSession.InterruptionOptions(rawValue: $0)
            }
            if options?.contains(.shouldResume) == true, !isPlaying {
                applyAudioSession()
                resume()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange() {
        // Headphones pulled out: keep playing out loud, which is the platform
        // default and what a learner doing dictation expects, but make sure
        // the session is still configured for the new route.
        guard isPlaying else { return }
        applyAudioSession()
    }

    // MARK: - Now Playing and remote commands

    /// Publishes metadata for the lock screen and Control Center.
    ///
    /// Without this the app's background-audio capability is useless: the audio
    /// continues, but the learner cannot see what is playing or pause it from
    /// the lock screen. A dictation set is exactly the situation where the
    /// phone is face-down and the lock screen is the only UI available.
    private func updateNowPlaying() {
        guard let clip else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: clip.title ?? clip.text ?? "Audio",
            MPMediaItemPropertyArtist: "English Learning",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? (Double(playbackRate)) : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Wires the lock-screen and Control Center buttons.
    ///
    /// Handlers return `.commandFailed` when there is no clip, so the system
    /// greys the buttons out instead of accepting a tap that does nothing.
    private func installRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()

        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.clip != nil else { return .commandFailed }
                self.resume()
                return .success
            }
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.clip != nil else { return .commandFailed }
                self.pause()
                return .success
            }
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.clip != nil else { return .commandFailed }
                self.togglePlayback()
                return .success
            }
        }
        commands.skipForwardCommand.preferredIntervals = [10]
        commands.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.player != nil else { return .commandFailed }
                self.skip(by: 10)
                return .success
            }
        }
        commands.skipBackwardCommand.preferredIntervals = [10]
        commands.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.player != nil else { return .commandFailed }
                self.skip(by: -10)
                return .success
            }
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            Task { @MainActor [weak self] in
                guard
                    let self,
                    self.player != nil,
                    let event = event as? MPChangePlaybackPositionCommandEvent
                else { return .commandFailed }
                self.seek(to: event.positionTime)
                return .success
            }
        }
    }

    // MARK: - Clock

    private func startTicker() {
        clearTicker()
        // 0.25s is below the threshold where a time label looks frozen and
        // above the threshold where a timer is meaningful battery cost.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func clearTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let player else { return }
        elapsed = player.currentTime
        if !player.isPlaying, isPlaying {
            // The delegate fires too, but a tick that lands first means the
            // repeat counter can never advance twice for one clip.
            handleClipFinished()
            return
        }
        updateNowPlaying()
    }

    /// One play of the clip has ended. Honours loop and the repeat counter.
    private func handleClipFinished() {
        completedPlays += 1
        if isLooping || completedPlays < repeatCount {
            replay()
        } else {
            isPlaying = false
            elapsed = duration
            clearTicker()
            updateNowPlaying()
        }
    }

    private func applyRate() {
        guard let player, isPlaying else { return }
        player.rate = playbackRate
        updateNowPlaying()
    }

    /// The clip's own rate scaled by the speed control, for speech only.
    private var scaledSpeechRate: Float {
        let base = clip?.speakingRate ?? AVSpeechUtterance.defaultSpeakingRate
        return max(AVSpeechUtteranceMinimumSpeechRate, min(base * playbackRate, AVSpeechUtteranceMaximumSpeechRate))
    }

    /// A rough spoken duration, in seconds.
    ///
    /// Roughly 14 characters per second at the default rate, scaled linearly.
    /// It is an estimate, and it is marked as one, because `AVSpeechUtterance`
    /// will not tell us the real length until it has been spoken.
    private func estimatedSpeechDuration(text: String, rate: Float) -> TimeInterval {
        let base = Double(text.count) / 14.0
        let defaultRate = Double(AVSpeechUtterance.defaultSpeakingRate)
        return max(0.5, base * (defaultRate / Double(max(rate, 0.1))))
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayerModel: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.handleClipFinished() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            self?.isPlaying = false
            self?.errorMessage = "This audio file could not be decoded."
        }
    }
}

// MARK: - SpeechPlaying conformance

extension AudioPlayerModel: SpeechPlaying {
    /// Speaks arbitrary text through the same synthesizer the player uses, so
    /// an example-sentence tap and a clip play can never talk over each other.
    public func speak(_ text: String, rate: Float, completion: (() -> Void)?) {
        speech.stop()
        speech.speak(text, rate: rate) { [weak self] in
            completion?()
            MainActor.assumeIsolated { self?.isPlaying = false }
        }
    }

    public func stop() {
        speech.stop()
        isPlaying = false
    }
}

// MARK: - MediaResolving

extension AudioPlayerModel: MediaResolving {
    /// A `file` clip's URL inside the app bundle, or `nil` for the other kinds.
    public nonisolated func localURL(for clip: AudioClip) -> URL? {
        guard clip.kind == .file, let fileName = clip.fileName else { return nil }
        if let url = Bundle.main.url(forResource: fileName, withExtension: nil) { return url }
        let parts = fileName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return Bundle.main.url(forResource: parts[1], withExtension: nil, subdirectory: parts[0])
    }

    /// A `video` clip's URL, or `nil` when the source is `.none`.
    ///
    /// `.none` returning `nil` is the correct answer, not a failure: the
    /// architecture treats "no video" as a complete state.
    public nonisolated func playableURL(for clip: VideoClip) -> URL? {
        clip.source.url
    }
}
