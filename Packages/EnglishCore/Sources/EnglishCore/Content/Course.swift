import Foundation

/// A difficulty tier shared by topics, lessons, exercises, and vocabulary words.
public enum Level: String, Codable, Sendable, Hashable, CaseIterable {
    case beginner
    case intermediate
    case advanced
}

/// The kind of study a topic represents, used for topic-card grouping.
public enum TopicKind: String, Codable, Sendable, Hashable, CaseIterable {
    case grammar
    case alphabet
    case methods
    case listening
    case speaking
    case reading
    case writing
    case ielts
    case vocabulary
}

/// The course index, decoded from `content.json`.
///
/// `topicIDs` is the canonical ordering used by ``ContentLibrary/allTopics``
/// and therefore by ``ContentLibrary/nextLesson(after:)``.
public struct Course: Codable, Sendable, Hashable, Identifiable {
    /// Stable identifier of the course index.
    public var id: String = "english-core"
    /// Display title of the course.
    public var title: String
    /// One or two sentences describing the course.
    public var description: String
    /// Every topic id in canonical study order.
    public var topicIDs: [String]
    /// Id of the primary vocabulary deck, when the course ships one.
    public var vocabularyDeckID: String?
    /// Ids of the IELTS modules bundled with the course.
    public var ieltsModuleIDs: [String]

    public init(
        id: String = "english-core",
        title: String,
        description: String,
        topicIDs: [String],
        vocabularyDeckID: String? = nil,
        ieltsModuleIDs: [String] = []
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.topicIDs = topicIDs
        self.vocabularyDeckID = vocabularyDeckID
        self.ieltsModuleIDs = ieltsModuleIDs
    }
}

/// A course unit grouping an ordered list of lessons.
public struct Topic: Codable, Sendable, Hashable, Identifiable {
    /// Stable kebab-case id, used as the progress foreign key.
    public let id: String
    /// Display title.
    public var title: String
    /// Study category of the topic.
    public var kind: TopicKind
    /// Difficulty of the topic as a whole.
    public var level: Level
    /// One or two sentences shown on the topic card.
    public var summary: String
    /// SF Symbol name shown on the topic card.
    public var icon: String
    /// Expected time to finish the topic, in minutes.
    public var estimatedMinutes: Int = 20
    /// Lessons in study order; at least one.
    public var lessons: [Lesson]

    public init(
        id: String,
        title: String,
        kind: TopicKind,
        level: Level,
        summary: String,
        icon: String,
        estimatedMinutes: Int = 20,
        lessons: [Lesson]
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.level = level
        self.summary = summary
        self.icon = icon
        self.estimatedMinutes = estimatedMinutes
        self.lessons = lessons
    }
}

/// A single lesson inside a topic.
public struct Lesson: Codable, Sendable, Hashable, Identifiable {
    /// Stable kebab-case id, unique across the course.
    public let id: String
    /// Display title.
    public var title: String
    /// One-line description of what the lesson covers.
    public var summary: String
    /// Difficulty, inherited from the topic when the JSON omits it.
    public var level: Level?
    /// XP awarded on completion; defaults to 30.
    public var xp: Int = 30
    /// Ordered steps; at least one.
    public var steps: [LessonStep]

    public init(
        id: String,
        title: String,
        summary: String,
        level: Level? = nil,
        xp: Int = 30,
        steps: [LessonStep]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.level = level
        self.xp = xp
        self.steps = steps
    }

    /// The lesson difficulty, falling back to `fallback` when the JSON omits it.
    public func resolvedLevel(fallback: Level) -> Level {
        level ?? fallback
    }

    /// Every inline exercise carried by the lesson, in step order.
    ///
    /// O(steps): builds a new array on each access.
    public var exercises: [Exercise] {
        steps.flatMap(\.exercises)
    }
}
