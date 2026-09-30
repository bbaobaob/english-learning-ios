import Foundation
import AVFoundation
import CryptoKit

/// Renders a speech utterance to an audio file on disk, once, and caches it.
///
/// **Why this exists.** `AVSpeechUtterance` cannot be paused, cannot be
/// scrubbed, and cannot be relied on to continue in the background. That means
/// the direct synthesizer path cannot satisfy three of the app's stated
/// requirements: a draggable scrubber, slow replay below the TTS floor, and
/// lock-screen / Control Center transport.
///
/// The fix is to stop treating the synthesizer as a player. `write(_:toBufferCallback:)`
/// renders an utterance to PCM buffers, which go into an `AVAudioFile`; from
/// then on the clip is an ordinary file and goes through the same
/// `AVAudioPlayer` path as a `file` clip, where all three work.
///
/// The cache key is `(text, rate, voice)`, so re-opening a lesson is free and
/// changing the speed renders a second file rather than mutating the first.
enum SpeechFileRenderer {

    /// The errors this can fail with. Both are surfaced rather than swallowed:
    /// a clip that silently will not play is indistinguishable from a learner
    /// who is not tapping the button.
    enum RenderError: Error, LocalizedError {
        /// The synthesizer reported the utterance as impossible to render.
        case synthesisFailed
        /// The buffer callback produced no audio data at all.
        case noAudioData

        var errorDescription: String? {
            switch self {
            case .synthesisFailed:
                return "This sentence could not be prepared for playback."
            case .noAudioData:
                return "This sentence produced no audio."
            }
        }
    }

    /// A cache entry's identity.
    struct Key: Hashable {
        let text: String
        /// The utterance rate, quantised so that two requests a fraction apart
        /// hit the same file rather than rendering near-duplicates.
        let rate: Int
        let voiceID: String?

        init(text: String, rate: Float, voiceID: String?) {
            self.text = text
            // Four significant figures is finer than any voice can resolve and
            // coarser than float noise, so repeated playbacks of the same
            // preset reuse one file.
            self.rate = Int((rate * 10_000).rounded())
            self.voiceID = voiceID
        }
    }

    // MARK: - Cache location

    /// The directory cached speech is written to.
    ///
    /// `cachesDirectory`, not `documentDirectory`: this is regenerable data, and
    /// putting it in Documents would make it visible in Files and eligible for
    /// iCloud backup, which is wrong for a few megabytes of synthesised speech
    /// the app can rebuild on demand.
    static var cacheDirectory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("SpeechCache", isDirectory: true)
    }

    /// The file for `key`, whether or not it has been rendered.
    static func url(for key: Key) -> URL? {
        guard let directory = cacheDirectory else { return nil }
        return directory.appendingPathComponent("\(fileName(for: key)).m4a")
    }

    /// A stable, filesystem-safe name for `key`.
    ///
    /// SHA256 over the fields rather than the text itself: an English sentence
    /// contains spaces, slashes, and apostrophes, and truncating the text to
    /// build a filename produces collisions between sentences that share a
    /// prefix — which is most of them in a lesson on one grammar point.
    static func fileName(for key: Key) -> String {
        let payload = "\(key.rate)|\(key.voiceID ?? "")|\(key.text)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The same naming, exposed for ``SpeechAudioSelfCheck``.
    ///
    /// Exists so the check exercises the real function rather than a
    /// reimplementation of it — a test that copies the logic under test proves
    /// nothing about the logic.
    static func fileNameForTesting(_ key: Key) -> String {
        fileName(for: key)
    }

    /// The cached file for `key`, if it has already been rendered.
    ///
    /// A zero-byte file counts as *not* rendered. That state should be
    /// unreachable — the render deletes the file on both failure paths — but
    /// checking here means a file left behind by a crash mid-write, or by a
    /// future change to the cleanup, cannot be handed out as a clip that opens
    /// successfully and plays silence.
    static func cachedURL(for key: Key) -> URL? {
        guard let url = url(for: key) else { return nil }
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber,
            size.intValue > 0
        else { return nil }
        return url
    }

    // MARK: - Rendering

    /// Returns a playable file for `key`, rendering it if necessary.
    ///
    /// - Parameters:
    ///   - key: The text, rate, and voice to render.
    ///   - completion: Receives the file URL, or a failure.
    ///
    /// - Important: `completion` is called on **whichever queue produced the
    ///   result** — the calling thread for an error or a cache hit, and
    ///   ``bufferQueue`` for a rendered buffer. It is not main-actor isolated.
    ///   Callers must hop themselves; ``AudioPlayerModel`` does so with
    ///   `Task { @MainActor in … }`, which also means a cache hit takes the same
    ///   path as a slow render and cannot re-enter its caller.
    static func render(
        key: Key,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        if let cached = cachedURL(for: key) {
            completion(.success(cached))
            return
        }
        guard let directory = cacheDirectory else {
            completion(.failure(RenderError.synthesisFailed))
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            completion(.failure(error))
            return
        }
        guard let destination = url(for: key) else {
            completion(.failure(RenderError.synthesisFailed))
            return
        }

        // The synthesizer is a local, function-scoped instance rather than the
        // app's shared one. `write(_:toBufferCallback:)` is a *separate*
        // rendering path from `speak(_:)`, and running it on the shared
        // synthesizer would have the two fighting over the same audio session —
        // a sentence the learner is hearing would stutter while a cache entry
        // is being built for the next one.
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: key.text)

        // Rate, voice, and delays are all configured *before* anything is
        // enqueued. `rate` in particular is read at `speak`/`write` time:
        // assigning it afterwards has no effect at all, which is the classic
        // silent-slow-replay bug.
        utterance.rate = Float(key.rate) / 10_000
        if let voiceID = key.voiceID {
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceID)
        }
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0

        // `write` hands back a buffer at a time and signals the end of the
        // utterance with an empty one. The file is opened lazily on the first
        // non-empty buffer, because there is no buffer to take a sample rate
        // from before then.
        var audioFile: AVAudioFile?
        var wroteAnything = false
        // Latches on the first terminal event. Without it an error mid-render
        // would report a failure and then the end-of-utterance signal would
        // report a *second*, contradictory result — and the caller would
        // install whichever landed last.
        var settled = false

        synthesizer.write(utterance) { buffer in
            // The callback arrives on an arbitrary queue, and everything below
            // touches `audioFile` and the flags, so it is confined to one serial
            // queue rather than racing between buffers.
            bufferQueue.sync {
                guard !settled else { return }

                // Length lives on the PCM subclass; anything else ends the render.
                if ((buffer as? AVAudioPCMBuffer)?.frameLength ?? 0) == 0 {
                    // End of utterance. An utterance that produced no audio at
                    // all — a voice with nothing for this text, or a synthesis
                    // that failed silently — is a failure, not a zero-byte
                    // success: `AVAudioPlayer` would open it and never play.
                    settled = true
                    if wroteAnything {
                        // Close before reporting: `AVAudioFile` finalises its
                        // header on deinit, so a caller that opened the file
                        // while this reference was still alive could read a
                        // truncated header.
                        audioFile = nil
                        completion(.success(destination))
                    } else {
                        // No audio means a zero-byte file may still exist. Left
                        // behind, the *next* lookup would find it via
                        // `cachedURL` and hand out a clip that plays nothing.
                        try? FileManager.default.removeItem(at: destination)
                        completion(.failure(RenderError.noAudioData))
                    }
                    return
                }

                do {
                    if audioFile == nil {
                        // A fresh file per render: reusing one would append this
                        // sentence to whatever the previous cache entry left.
                        audioFile = try AVAudioFile(
                            forWriting: destination,
                            settings: buffer.format.settings
                        )
                    }
                    try audioFile?.write(from: buffer)
                    wroteAnything = true
                } catch {
                    // Settle *before* reporting, so the end-of-utterance signal
                    // that follows is ignored.
                    settled = true
                    // A partially written file is worse than none: a later
                    // cache hit would open a truncated sentence and play it as
                    // if it were complete.
                    try? FileManager.default.removeItem(at: destination)
                    completion(.failure(error))
                }
            }
        }
    }

    /// Serialises the buffer callback. `AVSpeechSynthesizer` may call the
    /// callback from more than one queue, and `AVAudioFile` is not documented
    /// as safe for that.
    private static let bufferQueue = DispatchQueue(label: "app.speech.render")

    /// Empties the cache.
    ///
    /// ponytail: a wholesale delete with no size accounting or LRU. The cache is
    /// a few megabytes for a normal study session and is bounded by the
    /// system's own cache purging, so a real eviction policy is only worth
    /// building if the app is ever shipped with long offline audio lessons.
    static func clearCache() {
        guard let directory = cacheDirectory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    /// The cache's total size in bytes, for a diagnostics row in Profile.
    static func cacheSizeInBytes() -> Int64 {
        guard let directory = cacheDirectory else { return 0 }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        return contents.reduce(into: Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
    }
}
