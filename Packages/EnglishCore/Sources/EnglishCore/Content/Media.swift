import Foundation

/// Where an audio clip's audio comes from.
public enum AudioClipKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// Synthesized speech from `text`; needs no bundled asset.
    case speech
    /// A file inside the app bundle.
    case file
    /// A remote URL.
    case remote
}

/// A playable audio stimulus.
public struct AudioClip: Codable, Sendable, Hashable, Identifiable {
    /// Stable id used for bookmarks.
    public let id: String
    /// The source kind; defaults to `.speech`.
    public var kind: AudioClipKind = .speech
    /// Spoken text; required when `kind == .speech`.
    public var text: String?
    /// File name; required when `kind == .file`.
    public var fileName: String?
    /// Remote URL; required when `kind == .remote`.
    public var url: URL?
    /// `AVSpeechUtterance.defaultSpeakingRate`; 0.3 is slow.
    public var rate: Double?
    /// Optional voice override.
    public var voiceID: String?
    /// Optional title shown in the player.
    public var title: String?

    public init(
        id: String,
        kind: AudioClipKind = .speech,
        text: String? = nil,
        fileName: String? = nil,
        url: URL? = nil,
        rate: Double? = nil,
        voiceID: String? = nil,
        title: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.fileName = fileName
        self.url = url
        self.rate = rate
        self.voiceID = voiceID
        self.title = title
    }

    /// The speaking rate to hand to the speech synthesizer.
    public var speakingRate: Float {
        Float(rate ?? 0.5)
    }
}

/// Where a video's bytes come from.
public enum VideoSource: Codable, Sendable, Hashable {
    /// A remote URL.
    case remote(URL)
    /// A file name inside the app bundle.
    case bundled(String)
    /// No video; the lesson renders a placeholder.
    case none

    /// The `type` discriminator values.
    public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
        case remote
        case bundled
        case none
    }

    /// The source kind.
    public var kind: Kind {
        switch self {
        case .remote: .remote
        case .bundled: .bundled
        case .none: .none
        }
    }

    /// The playable URL when the source names one.
    public var url: URL? {
        switch self {
        case .remote(let url): url
        case .bundled(let name): URL(fileURLWithPath: name)
        case .none: nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case url
        case name
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .remote:
            self = .remote(try container.decode(URL.self, forKey: .url))
        case .bundled:
            self = .bundled(try container.decode(String.self, forKey: .name))
        case .none:
            self = .none
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)
        switch self {
        case .remote(let url): try container.encode(url, forKey: .url)
        case .bundled(let name): try container.encode(name, forKey: .name)
        case .none: break
        }
    }
}

/// One timed subtitle or transcript line.
public struct SubtitleCue: Codable, Sendable, Hashable, Identifiable {
    /// Cue start time in seconds; also the cue identity.
    public var id: Double { start }
    /// Start time in seconds.
    public var start: Double
    /// End time in seconds.
    public var end: Double
    /// The spoken or written line.
    public var text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// A playable video stimulus.
public struct VideoClip: Codable, Sendable, Hashable, Identifiable {
    /// Stable id used for bookmarks.
    public let id: String
    /// Title shown above the player.
    public var title: String
    /// Where the bytes come from; defaults to `.none`.
    public var source: VideoSource = .none
    /// Transcript lines shown in the transcript sheet.
    public var transcript: [String] = []
    /// Timed subtitles.
    public var subtitles: [SubtitleCue] = []
    /// Known duration in seconds, when the content declares one.
    public var durationSeconds: Double?

    public init(
        id: String,
        title: String = "",
        source: VideoSource = .none,
        transcript: [String] = [],
        subtitles: [SubtitleCue] = [],
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.transcript = transcript
        self.subtitles = subtitles
        self.durationSeconds = durationSeconds
    }
}

/// One dictation prompt; the canonical sentence is the clip's speech text.
public struct DictationItem: Codable, Sendable, Hashable, Identifiable {
    /// Stable id inside its step.
    public let id: String
    /// The audio to transcribe; its `text` is the canonical sentence.
    public var audio: AudioClip
    /// Extra accepted sentences; all go through the answer normalizer.
    public var acceptedAnswers: [String] = []
    /// Optional hint shown on request.
    public var hint: String?
    /// Optional Vietnamese translation revealed after grading.
    public var translation: String?
    /// XP awarded on a correct dictation.
    public var xp: Int = 15

    /// The sentence the learner is expected to type.
    public var expectedText: String {
        audio.text ?? ""
    }

    public init(
        id: String,
        audio: AudioClip,
        acceptedAnswers: [String] = [],
        hint: String? = nil,
        translation: String? = nil,
        xp: Int = 15
    ) {
        self.id = id
        self.audio = audio
        self.acceptedAnswers = acceptedAnswers
        self.hint = hint
        self.translation = translation
        self.xp = xp
    }
}
