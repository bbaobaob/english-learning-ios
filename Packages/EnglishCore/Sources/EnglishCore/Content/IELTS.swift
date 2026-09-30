import Foundation

/// One of the four IELTS papers.
public enum IELTSSkill: String, Codable, Sendable, Hashable, CaseIterable {
    case listening
    case reading
    case writing
    case speaking
}

/// One question inside an IELTS lesson.
public struct IELTSQuestion: Codable, Sendable, Hashable, Identifiable {
    /// The IELTS-specific question formats.
    public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
        case multipleChoice
        case matching
        case formCompletion
        case noteCompletion
        case sentenceCompletion
        case mapLabeling
        case diagramLabeling
        case dictation
        case trueFalseNotGiven
        case yesNoNotGiven
        case matchingHeadings
        case matchingInformation
        case summaryCompletion
    }

    /// Stable id inside its lesson.
    public let id: String
    /// The IELTS question format.
    public var kind: Kind
    /// The question text.
    public var prompt: String
    /// Optional instruction override.
    public var instruction: String?
    /// Options, word bank, or map labels.
    public var items: [ExerciseItem] = []
    /// The expected answer.
    public var answer: Answer = .none
    /// Shown after grading.
    public var explanation: String = ""
    /// XP awarded for a correct answer.
    public var xp: Int = 10

    public init(
        id: String,
        kind: Kind,
        prompt: String,
        instruction: String? = nil,
        items: [ExerciseItem] = [],
        answer: Answer = .none,
        explanation: String = "",
        xp: Int = 10
    ) {
        self.id = id
        self.kind = kind
        self.prompt = prompt
        self.instruction = instruction
        self.items = items
        self.answer = answer
        self.explanation = explanation
        self.xp = xp
    }
}

/// One practice lesson inside an IELTS module.
public struct IELTSLesson: Codable, Sendable, Hashable, Identifiable {
    /// Stable id, e.g. `ielts-l-sec1`.
    public let id: String
    /// Display title.
    public var title: String
    /// Target band, e.g. `5.5`.
    public var band: String?
    /// Expected duration in minutes.
    public var minutes: Int?
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
        band: String? = nil,
        minutes: Int? = nil,
        transcript: [String] = [],
        audio: AudioClip? = nil,
        items: [IELTSQuestion] = [],
        review: [String] = []
    ) {
        self.id = id
        self.title = title
        self.band = band
        self.minutes = minutes
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
    /// Which paper this module covers.
    public var skill: IELTSSkill
    /// Display title.
    public var title: String
    /// Lessons in study order.
    public var lessons: [IELTSLesson] = []

    public init(id: String, skill: IELTSSkill, title: String, lessons: [IELTSLesson] = []) {
        self.id = id
        self.skill = skill
        self.title = title
        self.lessons = lessons
    }
}
