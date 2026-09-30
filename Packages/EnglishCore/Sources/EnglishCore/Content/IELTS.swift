import Foundation

/// One of the four IELTS papers.
public enum IELTSSkill: String, Codable, Sendable, Hashable, CaseIterable {
    case listening
    case reading
    case writing
    case speaking
}

/// One question inside an IELTS lesson.
///
/// An IELTS question is an ordinary ``Exercise`` — the paper formats (form
/// completion, map labelling, True/False/Not Given) are expressed with the same
/// `ExerciseKind` cases as the rest of the course, and grading goes through the
/// same `ExerciseEngine`.
///
/// ponytail: a dedicated 13-case IELTS question enum was removed here. No
/// shipped question used it, and keeping a second parallel type meant
/// `ContentLibrary` silently failed to decode every IELTS module. Reintroduce
/// one only if a format genuinely cannot be expressed as an `ExerciseKind`.
public typealias IELTSQuestion = Exercise

/// One practice lesson inside an IELTS module.
public struct IELTSLesson: Codable, Sendable, Hashable, Identifiable {
    /// Stable id, e.g. `ielts-l-sec1`.
    public let id: String
    /// Display title.
    public var title: String
    /// The paper this lesson belongs to.
    ///
    /// A module may hold more than one paper — listening and reading ship
    /// together — so the lesson is the authoritative source and this defaults
    /// to the module's label when omitted.
    public var skill: IELTSSkill?
    /// Target band, e.g. `5.5`.
    public var band: String?
    /// Expected duration in minutes.
    public var minutes: Int?
    /// The task text or passage heading shown above the lesson.
    public var prompt: String?
    /// Vietnamese rendering of ``prompt``.
    public var translation: String?
    /// Transcript lines shown after the attempt.
    public var transcript: [String] = []
    /// The passage or prompt audio.
    public var audio: AudioClip?
    /// The questions.
    public var items: [IELTSQuestion] = []
    /// Coaching notes reviewed after the attempt.
    public var review: [String] = []

    public init(
        id: String,
        title: String,
        skill: IELTSSkill? = nil,
        band: String? = nil,
        minutes: Int? = nil,
        prompt: String? = nil,
        translation: String? = nil,
        transcript: [String] = [],
        audio: AudioClip? = nil,
        items: [IELTSQuestion] = [],
        review: [String] = []
    ) {
        self.id = id
        self.title = title
        self.skill = skill
        self.band = band
        self.minutes = minutes
        self.prompt = prompt
        self.translation = translation
        self.transcript = transcript
        self.audio = audio
        self.items = items
        self.review = review
    }
}

/// An IELTS paper bundled with the course.
public struct IELTSModule: Codable, Sendable, Hashable, Identifiable {
    /// Stable module id, e.g. `ielts-listening`.
    public let id: String
    /// Which paper this module leads with.
    ///
    /// One module can carry more than one paper — listening and reading ship
    /// together — so this is only the module's headline label. Use ``skills``
    /// or a lesson's own ``skill`` for anything that must be correct.
    public var skill: IELTSSkill?
    /// Display title.
    public var title: String
    /// Lessons in study order.
    public var lessons: [IELTSLesson] = []

    public init(id: String, skill: IELTSSkill? = nil, title: String, lessons: [IELTSLesson] = []) {
        self.id = id
        self.skill = skill
        self.title = title
        self.lessons = lessons
    }

    /// The distinct papers this module actually contains.
    ///
    /// - Complexity: O(*n*), where *n* is the number of lessons.
    public var skills: [IELTSSkill] {
        var seen = Set<IELTSSkill>()
        var ordered: [IELTSSkill] = []
        for lesson in lessons {
            let resolved = lesson.skill ?? skill
            if let resolved, seen.insert(resolved).inserted { ordered.append(resolved) }
        }
        return ordered
    }
}
