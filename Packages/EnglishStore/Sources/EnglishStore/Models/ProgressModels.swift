import Foundation
import SwiftData

/// The single learner profile row.
///
/// There is exactly one of these per install; the singleton is a convention
/// rather than a database constraint, so every access goes through
/// `ProgressStore`.
///
// ponytail: no unique key on this model — a second row is impossible today
// because only `ProgressStore` creates one. Add a unique `id` column the moment
// a second writer (widget, App Group extension) can exist.
@Model
public final class UserProfile {

    /// The learner's display name.
    public var name: String

    /// The instant the profile row was created.
    public var createdAt: Date

    /// The learner's daily XP goal, mirrored onto `StreakRecord` for display.
    public var dailyGoalXP: Int

    /// The instant onboarding finished, or `nil` while onboarding is unfinished.
    public var onboardedAt: Date?

    /// Creates a learner profile.
    ///
    /// - Parameters:
    ///   - name: The learner's display name.
    ///   - createdAt: The creation instant.
    ///   - dailyGoalXP: The daily XP goal.
    ///   - onboardedAt: The onboarding completion instant, if any.
    public init(name: String, createdAt: Date, dailyGoalXP: Int = 50, onboardedAt: Date? = nil) {
        self.name = name
        self.createdAt = createdAt
        self.dailyGoalXP = dailyGoalXP
        self.onboardedAt = onboardedAt
    }
}

/// Per-topic rollup of every exercise the learner has attempted in that topic.
@Model
public final class TopicProgress {

    /// The stable topic id; unique, so the rollup upserts by key.
    @Attribute(.unique) public var topicID: String

    /// Cached accuracy in `0...1`, always `correctCount / exercisesDone`.
    ///
    /// Stored rather than derived only so the topic list can sort on it without
    /// loading every attempt; `ProgressStore` keeps it consistent.
    public var accuracy: Double

    /// The number of graded exercises attempted in this topic.
    public var exercisesDone: Int

    /// The number of those attempts that were correct.
    public var correctCount: Int

    /// The instant the topic was first completed, or `nil` while unfinished.
    public var completedAt: Date?

    /// Creates a topic rollup.
    ///
    /// - Parameters:
    ///   - topicID: The stable topic id.
    ///   - accuracy: The cached accuracy in `0...1`.
    ///   - exercisesDone: The attempt count.
    ///   - correctCount: The correct-attempt count.
    ///   - completedAt: The completion instant, if any.
    public init(
        topicID: String,
        accuracy: Double = 0,
        exercisesDone: Int = 0,
        correctCount: Int = 0,
        completedAt: Date? = nil
    ) {
        self.topicID = topicID
        self.accuracy = accuracy
        self.exercisesDone = exercisesDone
        self.correctCount = correctCount
        self.completedAt = completedAt
    }
}

/// The learner's position inside one lesson, and the Home "Continue Learning" source.
@Model
public final class LessonProgress {

    /// The stable lesson id; unique, so the row upserts by key.
    @Attribute(.unique) public var lessonID: String

    /// The topic that owns the lesson.
    public var topicID: String

    /// The index of the step the learner should resume at.
    public var currentStepIndex: Int

    /// Whether the lesson's summary gate has been passed.
    public var completed: Bool

    /// The id of the last step the learner visited, for deep-link restore.
    public var lastStepID: String?

    /// The instant of the last progress change; drives the resume ordering.
    public var updatedAt: Date

    /// Creates a lesson position row.
    ///
    /// - Parameters:
    ///   - lessonID: The stable lesson id.
    ///   - topicID: The owning topic id.
    ///   - currentStepIndex: The index to resume at.
    ///   - completed: Whether the lesson is finished.
    ///   - lastStepID: The last visited step id, if any.
    ///   - updatedAt: The instant of this change.
    public init(
        lessonID: String,
        topicID: String,
        currentStepIndex: Int = 0,
        completed: Bool = false,
        lastStepID: String? = nil,
        updatedAt: Date
    ) {
        self.lessonID = lessonID
        self.topicID = topicID
        self.currentStepIndex = currentStepIndex
        self.completed = completed
        self.lastStepID = lastStepID
        self.updatedAt = updatedAt
    }
}

/// One immutable graded attempt, kept as the raw material for stats and debugging.
@Model
public final class AttemptRecord {

    /// The stable exercise id that was attempted.
    public var exerciseID: String

    /// The topic the exercise belongs to, used for weak-area stats.
    public var topicID: String

    /// Whether the attempt was graded correct.
    public var isCorrect: Bool

    /// The graded accuracy in `0...1`, not merely right-or-wrong.
    public var accuracy: Double

    /// The raw text the learner typed, when the exercise took free text.
    public var userText: String?

    /// The instant the attempt was recorded.
    public var createdAt: Date

    /// Creates an attempt record.
    ///
    /// - Parameters:
    ///   - exerciseID: The attempted exercise id.
    ///   - topicID: The owning topic id.
    ///   - isCorrect: Whether the attempt was correct.
    ///   - accuracy: The graded accuracy in `0...1`.
    ///   - userText: The raw learner input, if any.
    ///   - createdAt: The instant of the attempt.
    public init(
        exerciseID: String,
        topicID: String,
        isCorrect: Bool,
        accuracy: Double,
        userText: String? = nil,
        createdAt: Date
    ) {
        self.exerciseID = exerciseID
        self.topicID = topicID
        self.isCorrect = isCorrect
        self.accuracy = accuracy
        self.userText = userText
        self.createdAt = createdAt
    }
}
