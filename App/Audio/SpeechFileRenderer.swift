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
    private static func fileName(for key: Key) -> String {
        let payload = "\(key.rate)|\(key.voiceID ?? "")|\(key.text)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The cached file for `key`, if it has already been rendered.
    static func cachedURL(for key: Key) -> URL? {
        guard let url = url(for: key), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    // MARK: - Rendering

    /// Returns a playable file for `key`, rendering it if necessary.
    ///
    /// - Parameters:
    ///   - key: The text, rate, and voice to render.
    ///   - completion: Receives the file URL, or a failure. Called on the main
    ///     actor.
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

        // `write` hands back a buffer at a time and signals the end with an
        // empty one. The file is opened lazily on the first buffer, because
        // there is no buffer to take a sample rate from before then.
        var audioFile: AVAudioFile?
        var wroteAnything = false
        var failed = false

        synthesizer.write(utterance) { buffer in
            // The callback arrives on an arbitrary queue. Everything below
            // touches `audioFile` and the two flags, so it is confined to one
            // serial queue rather than racing between buffers.
            bufferQueue.sync {
                guard !failed else { return }

                if buffer.frameLength == 0 {
                    // End of utterance.
                    if !wroteAnything {
                        failed = true
                        completion(.failure(RenderError.noAudioData))
                    } else {
                        completion(.success(destination))
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
                    failed = true
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
