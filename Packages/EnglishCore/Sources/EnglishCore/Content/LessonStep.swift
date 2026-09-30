import Foundation

/// One unit of lesson content.
///
/// Encoded as a single JSON object whose `type` field selects the payload shape.
public enum LessonStep: Sendable, Hashable, Identifiable {
    case theory(TheoryStep)
    case video(VideoStep)
    case audio(AudioStep)
    case examples(ExamplesStep)
    case practice(PracticeStep)
    case exercises(ExercisesStep)
    case dictation(DictationStep)
    case listening(ListeningStep)
    case quiz(QuizStep)
    case summary(SummaryStep)

    /// The `type` discriminator value for this case.
    public var type: StepType {
        switch self {
        case .theory: .theory
        case .video: .video
        case .audio: .audio
        case .examples: .examples
        case .practice: .practice
        case .exercises: .exercises
        case .dictation: .dictation
        case .listening: .listening
        case .quiz: .quiz
        case .summary: .summary
        }
    }

    /// Step id, unique inside its lesson.
    public var id: String {
        switch self {
        case .theory(let step): step.id
        case .video(let step): step.id
        case .audio(let step): step.id
        case .examples(let step): step.id
        case .practice(let step): step.id
        case .exercises(let step): step.id
        case .dictation(let step): step.id
        case .listening(let step): step.id
        case .quiz(let step): step.id
        case .summary(let step): step.id
        }
    }

    /// Inline exercises carried by the step; empty for non-exercise steps.
    ///
    /// O(1): each case returns either a stored array or an empty literal.
    public var exercises: [Exercise] {
        switch self {
        case .exercises(let step): step.exercises
        case .listening(let step): step.exercises
        case .quiz(let step): step.questions
        default: []
        }
    }

    /// The raw strings used for the `type` discriminator.
    public enum StepType: String, Codable, Sendable, Hashable, CaseIterable {
        case theory
        case video
        case audio
        case examples
        case practice
        case exercises
        case dictation
        case listening
        case quiz
        case summary
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(StepType.self, forKey: .type) {
        case .theory: self = .theory(try TheoryStep(from: decoder))
        case .video: self = .video(try VideoStep(from: decoder))
        case .audio: self = .audio(try AudioStep(from: decoder))
        case .examples: self = .examples(try ExamplesStep(from: decoder))
        case .practice: self = .practice(try PracticeStep(from: decoder))
        case .exercises: self = .exercises(try ExercisesStep(from: decoder))
        case .dictation: self = .dictation(try DictationStep(from: decoder))
        case .listening: self = .listening(try ListeningStep(from: decoder))
        case .quiz: self = .quiz(try QuizStep(from: decoder))
        case .summary: self = .summary(try SummaryStep(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        switch self {
        case .theory(let step): try step.encode(to: encoder)
        case .video(let step): try step.encode(to: encoder)
        case .audio(let step): try step.encode(to: encoder)
        case .examples(let step): try step.encode(to: encoder)
        case .practice(let step): try step.encode(to: encoder)
        case .exercises(let step): try step.encode(to: encoder)
        case .dictation(let step): try step.encode(to: encoder)
        case .listening(let step): try step.encode(to: encoder)
        case .quiz(let step): try step.encode(to: encoder)
        case .summary(let step): try step.encode(to: encoder)
        }
    }
}

/// A rule inside a theory card.
public struct GrammarRule: Codable, Sendable, Hashable, Identifiable {
    /// Rule title, used as the identity.
    public var id: String { title }
    /// Short rule name.
    public var title: String
    /// The rule stated in one sentence.
    public var statement: String
    /// Optional structural formula, e.g. `Subject + will + base verb`.
    public var formula: String?
    /// Examples illustrating the rule.
    public var examples: [Example]

    public init(title: String, statement: String, formula: String? = nil, examples: [Example] = []) {
        self.title = title
        self.statement = statement
        self.formula = formula
        self.examples = examples
    }
}

/// A bilingual example sentence pair.
public struct Example: Codable, Sendable, Hashable, Identifiable {
    /// Stable id inside the owning rule or examples step.
    public let id: String
    /// The English sentence.
    public var en: String
    /// The Vietnamese translation.
    public var vi: String
    /// Optional usage note.
    public var note: String?

    public init(id: String, en: String, vi: String, note: String? = nil) {
        self.id = id
        self.en = en
        self.vi = vi
        self.note = note
    }
}

/// A scrollable theory card.
public struct TheoryStep: Codable, Sendable, Hashable, Identifiable {
    /// Step id, unique inside its lesson.
    public let id: String
    /// Card heading.
    public var heading: String
    /// Prose body of the card.
    public var body: String
    /// Rules explained by the card.
    public var rules: [GrammarRule]

    public init(id: String, heading: String = "", body: String = "", rules: [GrammarRule] = []) {
        self.id = id
        self.heading = heading
        self.body = body
        self.rules = rules
    }
}

/// A video playback step.
public struct VideoStep: Codable, Sendable, Hashable, Identifiable {
    /// Step id, unique inside its lesson.
    public let id: String
    /// The clip to play.
    public var video: VideoClip

    public init(id: String, video: VideoClip) {
        self.id = id
        self.video = video
    }
}

/// A full audio player step.
public struct AudioStep: Codable, Sendable, Hashable, Identifiable {
    /// Step id, unique inside its lesson.
    public let id: String
    /// The clip to play.
    public var audio: AudioClip
    /// Title shown in the player.
    public var title: String?

    public init(id: String, audio: AudioClip, title: String? = nil) {
        self.id = id
        self.audio = audio
        self.title = title
    }
}

/// A tappable list of examples.
public struct ExamplesStep: Codable, Sendable, Hashable, Identifiable {
    /// Step id, unique inside its lesson.
    public let id: String
    /// Examples to display.
    public var examples: [Example]

    public init(id: String, examples: [Example]) {
        self.id = id
        self.examples = examples
    }
}

/// A step that runs referenced exercises through the session flow.
public struct PracticeStep: Codable, Sendable, Hashable, Identifiable {
    /// Step id, unique inside its lesson.
    public let id: String
    /// Optional heading.
    public var title: String?
    /// Ids of the exercises to run.
    public var exerciseIDs: [String]

    public init(id: String, title: String? = nil, exerciseIDs: [String] = []) {
        self.id = id
        self.title = title
        self.exerciseIDs = exerciseIDs
    }
}

/// A step carrying self-contained inline exercises.
public struct ExercisesStep: Codable, Sendable, Hashable, Identifiable {
    /// Step id, unique inside its lesson.
    public let id: String
    /// Inline exercises.
    public var exercises: [Exercise]

    public init(id: String, exercises: [Exercise]) {
        self.id = id
        self.exercises = exercises
    }
}

/// A dictation set.
public struct DictationStep: Codable, Sendable, Hashable, Identifiable {
    /// Step id, unique inside its lesson.
    public let id: String
    /// Optional heading.
    public var title: String?
    /// Dictation items to run.
    public var items: [DictationItem]

    public init(id: String, title: String? = nil, items: [DictationItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

/// A listening comprehension set; audio is required.
public struct ListeningStep: Codable, Sendable, Hashable, Identifiable {
    /// Step id, unique inside its lesson.
    public let id: String
    /// Optional heading.
    public var title: String?
    /// The audio the questions refer to.
    public var audio: AudioClip?
    /// Comprehension exercises.
    public var exercises: [Exercise]

    public init(id: String, title: String? = nil, audio: AudioClip? = nil, exercises: [Exercise]) {
        self.id = id
        self.title = title
        self.audio = audio
        self.exercises = exercises
    }
}

/// A scored quiz step.
public struct QuizStep: Codable, Sendable, Hashable, Identifiable {
    /// Step id, unique inside its lesson.
    public let id: String
    /// Optional heading.
    public var title: String?
    /// Quiz questions.
    public var questions: [Exercise]
    /// Percentage required to pass; defaults to 70.
    public var passPercent: Double = 70

    public init(id: String, title: String? = nil, questions: [Exercise], passPercent: Double = 70) {
        self.id = id
        self.title = title
        self.questions = questions
        self.passPercent = passPercent
    }
}

/// The lesson summary and completion gate.
public struct SummaryStep: Codable, Sendable, Hashable, Identifiable {
    /// Step id, unique inside its lesson.
    public let id: String
    /// Takeaway bullets shown on the summary card.
    public var takeaways: [String]
    /// Id of the lesson to study next.
    public var nextLessonID: String?

    public init(id: String, takeaways: [String], nextLessonID: String? = nil) {
        self.id = id
        self.takeaways = takeaways
        self.nextLessonID = nextLessonID
    }
}
