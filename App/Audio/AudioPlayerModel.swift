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
/// **A `speech` clip is rendered to a file before it plays.**
/// `AVSpeechUtterance` cannot be paused, scrubbed, or reliably kept alive in
/// the background, so a speech clip played straight through the synthesizer
/// would quietly fail the scrubber, slow replay, and lock-screen transport —
/// while looking like it worked. Every speech clip therefore goes through
/// ``SpeechFileRenderer`` and plays as an ordinary `AVAudioPlayer`, and the
/// three transport paths become one.
///
/// The direct synthesizer survives for ``SpeechPlaying``: tapping a single
/// word or example sentence should be instant, and a one-shot utterance has no
/// scrubber to justify a render.
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

    /// Whether the queue plays in a shuffled order.
    ///
    /// Only meaningful with a queue of more than one clip — which is exactly
    /// what an `examples` step is, and what a bare single-clip lesson is not.
    /// The UI therefore only offers the toggle when the queue has more than one
    /// entry, so it never appears as a control that does nothing.
    ///
    /// ponytail: a seeded `shuffle()` on the current queue rather than a
    /// Fisher-Yates over a stored seed. A stored seed would make a shuffle
    /// reproducible across a re-render, which matters only if the learner needs
    /// to revisit the same order; add one if the examples list ever grows
    /// longer than a dozen items.
    var isShuffled: Bool = false {
        didSet {
            guard isShuffled != oldValue else { return }
            applyQueueOrder()
        }
    }

    /// The clips queued behind the current one, in play order.
    @ObservationIgnored
    private var queue: [AudioClip] = []

    /// Whether a queue is loaded. The shuffle toggle is only offered when this
    /// is `true` *and* the queue holds more than one clip.
    var hasShuffleableQueue: Bool { queue.count > 1 }

    /// How many times to play the clip before stopping. `1` means play once.
    /// Clamped to `1...20` — past that it is a loop, not a counter.
    var repeatCount: Int = 1 {
        didSet {
            // Clamped by assignment rather than by `min`/`max` at the use site,
            // so every reader sees a legal value and the setter cannot recurse:
            // `didSet` does not fire for the write it makes to itself.
            let clamped = min(max(repeatCount, 1), 20)
            if clamped != repeatCount { repeatCount = clamped }
        }
    }

    /// How many of the `repeatCount` plays have finished.
    private(set) var completedPlays: Int = 0

    /// The rate the *slow replay* button uses, as a fraction of normal speed.
    ///
    /// Slower than any speed-menu preset: slow replay is for hearing a single
    /// phoneme or a half-finished word, not for working through a sentence.
    ///
    /// This is a *player* rate applied to the rendered file, not a synthesizer
    /// rate. That distinction is not about how slow it can go —
    /// `AVSpeechUtteranceMinimumSpeechRate` is 0.0 on real devices, so speech
    /// can go slower than this too. It is that the file can be paused,
    /// scrubbed, and backgrounded, which an utterance cannot.
    static let slowRate: Float = SpeechRate.slowestFraction

    /// The cache's on-disk size, for a diagnostics row.
    var speechCacheSize: Int64 { SpeechFileRenderer.cacheSizeInBytes() }

    /// Runs the audio contract checks and returns their results.
    ///
    /// Surfaced on the type rather than only in a test target so a debug menu
    /// can call it on a real device, where `AVSpeechUtterance`'s actual bounds
    /// are the ones that matter — a simulator's voice set and rate range differ
    /// enough that passing there proves little.
    static func runSelfCheck() -> [SpeechAudioSelfCheck.Result] {
        SpeechAudioSelfCheck.run()
    }

    /// Empties the rendered-speech cache.
    ///
    /// ponytail: a whole-cache delete rather than an LRU. The cache is a few
    /// megabytes for a normal session and the system purges `Caches` under
    /// pressure anyway; a real eviction policy is only worth building if long
    /// offline audio lessons ever ship.
    func clearSpeechCache() {
        SpeechFileRenderer.clearCache()
    }

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

    /// The `AVAudioPlayer` delegate bridge. `AVAudioPlayer` holds its delegate
    /// weakly, so the model retains it explicitly for exactly as long as the
    /// player exists.
    @ObservationIgnored
    private lazy var playerDelegate: PlayerDelegateProxy = {
        let proxy = PlayerDelegateProxy()
        proxy.owner = self
        return proxy
    }()

    // MARK: - SpeechPlaying

    /// `true` while audio is in flight by *either* route: a clip playing from
    /// its rendered file, or a one-shot utterance going straight through the
    /// synthesizer.
    ///
    /// Both matter because the UI shows a speaking indicator for either, and a
    /// learner who taps an example mid-lesson must see the indicator appear
    /// even though no `AVPlayer` is running.
    public var isSpeaking: Bool { speech.isSpeaking || isPlaying }

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
    func play(_ clip: AudioClip, autoplay: Bool) {
        if self.clip?.id == clip.id, player != nil || isSpeaking {
            if autoplay, !isPlaying { resume() }
            return
        }
        stop()
        // A one-clip play clears any queue: the caller is not asking for a
        // sequence, so a queue left over from a previous list must not resume.
        queue = []
        load(clip, autoplay: autoplay)
    }

    /// Loads a *sequence* of clips, starting at `clip`.
    ///
    /// The shuffle toggle is only meaningful here — with one clip there is
    /// nothing to reorder — so this is the initialiser that makes
    /// ``isShuffled`` a real control rather than a decorative one.
    ///
    /// - Parameters:
    ///   - clip: The clip to start with.
    ///   - following: The clips to play after it, in order.
    ///   - autoplay: Start playing as soon as the first clip is ready.
    func play(_ clip: AudioClip, following: [AudioClip], autoplay: Bool) {
        stop()
        queue = following
        if isShuffled { applyQueueOrder() }
        load(clip, autoplay: autoplay)
    }

    /// The shared body of both `play` overloads: pick up `clip` as the loaded
    /// one, honouring the per-clip loop setting.
    private func load(_ clip: AudioClip, autoplay: Bool) {
        self.clip = clip
        completedPlays = 0
        errorMessage = nil
        // A per-clip loop setting, if one was remembered, wins over the global
        // toggle — otherwise a caller that loops one example would leave the
        // whole next clip looping too.
        if let remembered = loopByClipID[clip.id] {
            isLooping = remembered
        }
        applyAudioSession()

        // Two kinds are not playable the moment `load` returns: a `speech` clip
        // is still being rendered, and a `remote` one is still being
        // downloaded. Both hand the autoplay intent to their own completion
        // rather than having it acted on here, where `resume` would find no
        // player and silently do nothing.
        let isAsynchronous = clip.kind == .speech || clip.kind == .remote
        pendingAutoplay = autoplay && isAsynchronous

        switch clip.kind {
        case .speech:
            loadSpeech(clip)
        case .file:
            loadFile(clip)
        case .remote:
            loadRemote(clip)
        }
        if autoplay, !isAsynchronous { resume() }
    }

    /// Stops everything and releases the loaded clip.
    func stop() {
        speech.stop()
        player?.stop()
        player = nil
        isPlaying = false
        isLoading = false
        elapsed = 0
        duration = 0
        // Cleared so a stale render cannot start playing after a stop.
        pendingAutoplay = false
        // Bumped on every stop so a render that was in flight when the learner
        // moved on cannot install its player over the new clip.
        renderToken &+= 1
        clearTicker()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Starts or resumes from the current position.
    func resume() {
        guard let clip else { return }
        switch clip.kind {
        case .speech:
            // The clip is played from a rendered file, not from the live
            // synthesizer — see `loadSpeech`. If it is not ready yet, the render
            // completion starts it; calling `resume` again in the meantime is a
            // no-op rather than a second render.
            guard let player else { return }
            if player.currentTime >= player.duration, !player.isPlaying {
                player.currentTime = 0
            }
            player.enableRate = true
            player.play()
            isPlaying = true
            startTicker()
        case .file, .remote:
            guard let player else { return }
            player.enableRate = true
            player.play()
            isPlaying = true
            startTicker()
        }
        updateNowPlaying()
    }

    /// Pauses.
    ///
    /// Uniform across all three kinds because a speech clip is a rendered file
    /// by the time it is playing. There is no "stop and remember where I was"
    /// path any more, and there did not need to be one.
    func pause() {
        guard clip != nil else { return }
        player?.pause()
        isPlaying = false
        clearTicker()
        updateNowPlaying()
    }

    /// Play/pause, the single control the transport bar's main button uses.
    func togglePlayback() {
        isPlaying ? pause() : resume()
    }

    /// Restarts the clip from zero, keeping the current settings.
    ///
    /// Restores normal speed first: "replay" after a slow replay means "say it
    /// again", not "say it again at a crawl".
    ///
    /// While a speech clip is still rendering there is no file to rewind, so
    /// the intent is recorded and honoured by the render's completion — the
    /// same mechanism `pendingAutoplay` uses, which is why a learner who taps
    /// replay three times during a render hears the sentence once, from the
    /// start, rather than nothing.
    func replay() {
        guard clip != nil else { return }
        guard let player else {
            pendingAutoplay = true
            return
        }
        elapsed = 0
        player.currentTime = 0
        player.enableRate = true
        player.rate = playbackRate
        player.play()
        isPlaying = true
        startTicker()
        updateNowPlaying()
    }

    /// The first-class dictation and alphabet control: the same clip again, at
    /// a much lower rate.
    ///
    /// This is not `playbackRate = 0.5`. The speed control is a study tool the
    /// learner sets once; slow replay is a momentary action that always plays
    /// slowly and always from the start, because the words being listened for
    /// are at the beginning of the sentence.
    ///
    /// Slow replay is momentary, not sticky: the next ``replay()`` or a touch
    /// of the speed control returns the clip to normal speed, so a learner who
    /// taps it to hear one word does not then find the whole clip stuck at a
    /// crawl.
    func slowReplay() {
        guard clip != nil else { return }
        guard let player else {
            // Still rendering. The rate is recorded so the completion starts it
            // slowly rather than at normal speed.
            pendingAutoplay = true
            pendingSlowRate = Self.slowRate
            return
        }
        elapsed = 0
        player.currentTime = 0
        player.enableRate = true
        // A player rate on the rendered file, deliberately below every
        // speed-menu preset. See `slowRate`.
        player.rate = Self.slowRate
        isPlaying = true
        startTicker()
        updateNowPlaying()
    }

    /// Seeks to `seconds`, clamped to the clip.
    ///
    /// Uniform across all three clip kinds, because a speech clip is played
    /// from a rendered file and therefore has a real timeline. Before that
    /// change this had to special-case `.speech` and restart the utterance,
    /// which is why the scrubber used to be hidden for speech clips at all.
    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        let target = min(max(seconds, 0), max(player.duration, 0))
        player.currentTime = target
        elapsed = target
        updateNowPlaying()
    }

    /// Nudges the position by `seconds`, used by the 10-second skip controls.
    func skip(by seconds: TimeInterval) {
        seek(to: elapsed + seconds)
    }

    /// Turns looping on or off for the loaded clip, applying it immediately.
    ///
    /// Separate from setting `isLooping` directly so a screen can pass the value
    /// it toggled rather than doing the negation itself — six lanes inverting a
    /// bool by hand is six chances to get one of them backwards.
    func setLooping(_ isLooping: Bool) {
        self.isLooping = isLooping
    }

    /// Turns looping on or off for one named clip, and remembers it.
    ///
    /// For a screen that previews several clips in turn — an example list, a
    /// word deck — where the loop state is a property of the clip rather than
    /// of whatever happens to be loaded. The setting is stored per clip id and
    /// applied by ``play(_:autoplay:)`` when that clip is loaded, so toggling
    /// the loop on an example that is not playing yet is not lost.
    func setLooping(_ isLooping: Bool, for clip: AudioClip) {
        loopByClipID[clip.id] = isLooping
        if self.clip?.id == clip.id {
            self.isLooping = isLooping
        }
    }

    /// Per-clip loop settings, applied when a clip loads.
    @ObservationIgnored
    private var loopByClipID: [String: Bool] = [:]

    /// Appends one to the repeat counter, clamped to the legal range.
    func incrementRepeat() {
        repeatCount = min(repeatCount + 1, 20)
    }

    /// Subtracts one from the repeat counter, clamped to the legal range.
    func decrementRepeat() {
        repeatCount = max(repeatCount - 1, 1)
    }

    // MARK: - Loading

    /// Loads a `speech` clip by **rendering it to a file first**.
    ///
    /// This is the whole point of routing speech through the file cache. The
    /// live synthesizer cannot be paused, cannot be scrubbed, and cannot be
    /// relied on to continue in the background — so a speech clip played
    /// directly would silently fail the scrubber, real slow replay, and
    /// lock-screen transport while appearing to work.
    ///
    /// It is *not* about going slower than the synthesizer allows. That is
    /// already 0.0 on real devices. It is that a file can be paused, scrubbed,
    /// and backgrounded at all, which an utterance cannot.
    ///
    /// Once rendered, the clip is an ordinary `AVAudioPlayer`, and every
    /// transport control below works on it identically to a `file` clip.
    ///
    /// The render is asynchronous, so `isLoading` is `true` until it lands. A
    /// cache hit skips the render entirely, so a second visit to a lesson costs
    /// one `AVAudioPlayer` open and no synthesis at all.
    ///
    /// The completion is always hopped onto the main actor, even when the
    /// renderer answers synchronously on a cache hit. That is not incidental:
    /// calling `loadPlayer` inline from a cache hit would install a player and
    /// then re-enter this method's caller before `load` had finished, and the
    /// deferred hop makes both paths identical.
    private func loadSpeech(_ clip: AudioClip) {
        guard let text = clip.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "This clip has no text to speak."
            return
        }

        let key = SpeechFileRenderer.Key(
            text: text,
            rate: scaledSpeechRate,
            voiceID: clip.voiceID
        )
        // Identifies this render. A render that finishes after the learner has
        // moved to another clip installs nothing, which is the whole reason the
        // token exists — otherwise a slow render of lesson 1 lands on top of
        // lesson 2's player.
        renderToken &+= 1
        let token = renderToken

        // Show the estimated length immediately so the transport bar is not
        // empty while the render runs. The real duration replaces it the moment
        // the file opens.
        duration = estimatedSpeechDuration(text: text, rate: scaledSpeechRate)
        elapsed = 0
        isLoading = true

        SpeechFileRenderer.render(key: key) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Stale: the learner stopped or switched clips mid-render.
                guard token == self.renderToken else { return }
                isLoading = false

                switch result {
                case .success(let url):
                    loadPlayer(url: url, clip: clip)
                    // Read both intents *before* clearing them: they are what the
                    // learner asked for while the render was running, and a
                    // slow-replay tap implies "play" too.
                    let shouldPlay = pendingAutoplay || isPlaying
                    let slow = pendingSlowRate
                    pendingAutoplay = false
                    pendingSlowRate = nil
                    if let slow, let player {
                        player.rate = slow
                    }
                    if shouldPlay {
                        resume()
                    }
                case .failure(let error):
                    pendingAutoplay = false
                    pendingSlowRate = nil
                    errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? "This sentence could not be prepared for playback."
                }
            }
        }
    }

    /// Bumped on every load and every stop; see ``renderToken``.
    @ObservationIgnored
    private var renderToken: Int = 0

    /// Set when a render started with `autoplay` so the file starts as soon as
    /// it is ready rather than sitting silent until a second tap.
    @ObservationIgnored
    private var pendingAutoplay: Bool = false

    /// The rate to start a pending render at, when `slowReplay` was pressed
    /// before the file existed. `nil` means normal speed.
    @ObservationIgnored
    private var pendingSlowRate: Float?

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
        // Same token as the speech render: a download that lands after the
        // learner has moved on must not install a player over the new clip.
        renderToken &+= 1
        let token = renderToken

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard token == self.renderToken else { return }
                isLoading = false

                let shouldPlay = pendingAutoplay
                pendingAutoplay = false

                if let error {
                    errorMessage = "Audio could not be downloaded: \(error.localizedDescription)"
                    return
                }
                guard let data else {
                    errorMessage = "Audio could not be downloaded."
                    return
                }
                loadPlayerData(data, clip: clip)
                if shouldPlay { resume() }
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
            player.delegate = playerDelegate
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
            player.delegate = playerDelegate
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
    ///
    /// A `speech` clip reaches this point as a rendered file, so the lock screen
    /// gets a real duration and a real scrub position for a sentence too — the
    /// metadata is not second-class for TTS the way it would be if the
    /// synthesizer were driving playback.
    private func updateNowPlaying() {
        guard let clip else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: clip.title ?? clip.text ?? "Audio",
            MPMediaItemPropertyArtist: "English Learning",
            // The player's actual rate, not the speed control's value: after a
            // slow replay the two differ, and the lock screen has to show what
            // the learner is hearing.
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(player?.rate ?? playbackRate) : 0.0,
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
            // End of clip. The delegate normally reports this too, and both
            // paths funnel through `clipDidFinishPlaying`, which is guarded so
            // the repeat counter cannot advance twice for one play.
            clipDidFinishPlaying()
            return
        }
        updateNowPlaying()
    }

    /// The player could not decode its bytes. Surfaced rather than swallowed,
    /// because a clip that silently does nothing is indistinguishable from a
    /// learner who is not tapping play.
    func reportDecodeFailure() {
        isPlaying = false
        errorMessage = "This audio file could not be decoded."
    }

    /// One play of the clip has ended. Honours loop and the repeat counter.
    ///
    /// Re-entrancy guarded: the end of a clip is reported both by the delegate
    /// and by the next `tick()`, and whichever lands first flips `isPlaying`,
    /// so the second call returns immediately instead of counting two plays and
    /// skipping a repeat.
    func clipDidFinishPlaying() {
        guard isPlaying else { return }
        completedPlays += 1
        if isLooping || completedPlays < repeatCount {
            replay()
        } else if let next = queue.first {
            // A sequence is loaded, so roll on rather than stopping. Popping
            // before loading matters: `load` does not clear the queue, so a
            // leftover head would replay the same clip.
            queue.removeFirst()
            load(next, autoplay: true)
        } else {
            isPlaying = false
            elapsed = duration
            clearTicker()
            updateNowPlaying()
        }
    }

    /// Shuffles the queue in place when ``isShuffled`` is on.
    private func applyQueueOrder() {
        guard isShuffled else { return }
        queue.shuffle()
    }

    /// Applies the speed control to the running player.
    ///
    /// Only while playing: setting `AVAudioPlayer.rate` on a stopped player is
    /// accepted but is overwritten by the next `play()`, so writing it here
    /// would make the speed control look broken when the learner paused, changed
    /// speed, and pressed play.
    private func applyRate() {
        guard let player, isPlaying else { return }
        player.rate = playbackRate
        updateNowPlaying()
    }

    /// The rate a speech clip is **rendered** at: the clip's authored rate,
    /// scaled by the speed control, clamped to the bounds the synthesizer
    /// actually reports.
    ///
    /// This is the rate baked into the cache file, so it is only consulted when
    /// a render is requested. Once a speech clip is playing it is a plain audio
    /// file and the speed control acts on `AVAudioPlayer.rate` instead — which
    /// means the speed menu works on speech clips *without* re-rendering, and
    /// that the menu can offer rates the synthesizer would never honour.
    private var scaledSpeechRate: Float {
        // `AudioClip.rate` is authored in the content as an absolute
        // `AVSpeechUtterance` rate, defaulting to the system's normal rate. The
        // speed control is a multiplier on top of it, then clamped — an
        // out-of-range rate is silently ignored, not clamped for us.
        let base = clip?.speakingRate ?? SpeechRate.normal
        return min(max(base * playbackRate, SpeechRate.minimum), SpeechRate.maximum)
    }

    /// A rough spoken duration, in seconds, shown while a render is in flight.
    ///
    /// Roughly 14 characters per second at normal speed, scaled linearly. It is
    /// an estimate by necessity — `AVSpeechUtterance` will not report a length
    /// before it is spoken, and the file does not exist yet — but the real
    /// duration replaces it the moment the render lands, so nothing depends on
    /// this being accurate.
    private func estimatedSpeechDuration(text: String, rate: Float) -> TimeInterval {
        let charactersPerSecond = 14.0
        let base = Double(text.count) / charactersPerSecond
        // `max(rate, minimum)` rather than a literal floor: dividing by a rate of
        // zero would be an infinity, and the point is to express the ratio
        // against the system's own normal rate.
        let relativeToNormal = Double(SpeechRate.normal) / Double(max(rate, SpeechRate.minimum))
        return max(0.5, base * relativeToNormal)
    }
}

// MARK: - AVAudioPlayerDelegate

/// Forwards `AVAudioPlayer`'s callbacks to the model.
///
/// A separate `NSObject` subclass rather than making `AudioPlayerModel` itself
/// the delegate, for two reasons that both bite in practice: `AVAudioPlayer`
/// holds its delegate **weakly**, so a non-`NSObject` `@MainActor @Observable`
/// class is at the mercy of how Swift's observation machinery lays out its
/// storage; and an `@objc` protocol conformance on a `@MainActor` type forces
/// every requirement to be `nonisolated`, which pushes the state mutation into
/// a `Task` and out of the callback's ordering.
///
/// The proxy is retained by the model and does nothing but forward, so the
/// model's own isolation stays intact.
private final class PlayerDelegateProxy: NSObject, AVAudioPlayerDelegate {
    /// Set by the model. Weak, so the proxy never keeps a torn-down player
    /// alive.
    weak var owner: AudioPlayerModel?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Not `assumeIsolated`: `AVAudioPlayer` calls its delegate on an
        /// arbitrary queue, and `assumeIsolated` would trap if that queue is
        // not the main one. A `Task` hops correctly whatever the caller did.
        Task { @MainActor [owner] in
            owner?.clipDidFinishPlaying()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [owner] in
            owner?.reportDecodeFailure()
        }
    }
}

// MARK: - SpeechPlaying conformance

extension AudioPlayerModel: SpeechPlaying {
    /// Speaks arbitrary text through the shared synthesizer.
    ///
    /// This is the **direct** path, and it is deliberately separate from clip
    /// playback. A `SpeechPlaying` caller is tapping one word or one example
    /// sentence and wants it now; rendering a file first would add a perceptible
    /// delay to every tap, and the caller has no scrubber and no lock-screen
    /// controls to justify it. Clips loaded into the player take the rendered
    /// path instead — see ``loadSpeech(_:)``.
    ///
    /// Any clip currently playing is stopped first, so a one-shot utterance can
    /// never talk over a lesson's audio.
    public func speak(_ text: String, rate: Float, completion: (() -> Void)?) {
        player?.stop()
        isPlaying = false
        clearTicker()

        speech.speak(text, rate: rate) { [weak self] in
            completion?()
        }
    }

    /// Speaks `text` at the system's normal rate.
    ///
    /// Exists so a caller with no reason to pick a speed does not write one.
    /// Every hardcoded rate literal in the app is a guess about
    /// `AVSpeechUtterance.defaultSpeakingRate`, which is not a documented
    /// constant; making the normal-speed path the shortest one is what stops
    /// those guesses from accumulating.
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        speak(text, rate: SpeechRate.normal, completion: completion)
    }

    public func stop() {
        player?.stop()
        isPlaying = false
        clearTicker()
        speech.stop()
    }
}

extension AudioPlayerModel {
    /// Speaks `text` as slowly as the synthesizer allows.
    ///
    /// The slowest *direct* speech, for a one-shot tap where there is no player
    /// to render through. Below this the answer is a rendered file, not a
    /// quieter request — the synthesizer silently ignores an out-of-range rate
    /// rather than clamping it, so asking for less than it supports produces
    /// normal speed with no indication anything went wrong.
    func speakSlowly(_ text: String, completion: (() -> Void)? = nil) {
        speak(text, rate: SpeechRate.slowest, completion: completion)
    }

    /// Loads and plays a clip, with the transport's own defaults.
    ///
    /// `play(_:autoplay:)` already defaults `autoplay` to `true`; this exists so
    /// a call site reads as `play(clip)` rather than as a decision it did not
    /// make.
    func play(_ clip: AudioClip) {
        play(clip, autoplay: true)
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
