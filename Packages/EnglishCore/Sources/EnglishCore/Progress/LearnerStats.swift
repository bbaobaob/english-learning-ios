import Foundation

/// The learner's lifetime totals, as fed to ``AchievementEngine``.
///
/// Decoding tolerates missing keys, so adding a metric later cannot make an
/// existing progress file unreadable.
public struct LearnerStats: Sendable, Codable, Equatable, Hashable {

    /// The lifetime XP total.
    public var totalXP: Int

    /// The current study streak in days.
    public var streak: Int

    /// The number of lessons finished.
    public var lessonsCompleted: Int

    /// The lifetime accuracy in `0...1`.
    public var accuracy: Double

    /// The number of vocabulary items considered learned.
    public var wordsMastered: Int

    /// The number of dictation exercises answered perfectly.
    public var dictationsPassed: Int

    /// The number of review sessions completed.
    public var reviewsDone: Int

    /// The total time spent studying, in minutes.
    public var studyMinutes: Int

    /// The number of IELTS modules finished.
    public var ieltsCompleted: Int

    /// The number of lessons finished with every step answered correctly.
    public var perfectLessonRuns: Int

    /// The number of consecutive days the daily XP goal was met.
    public var dailyGoalStreak: Int

    /// The zeroed stats of a learner who has just installed the app.
    public static let empty = LearnerStats()

    /// Coding keys for the persisted stats payload.
    ///
    /// Declared explicitly because a hand-written `init(from:)` suppresses the
    /// compiler's synthesised conformance, including its `CodingKeys` -- without
    /// this enum neither direction of `Codable` resolves.
    private enum CodingKeys: String, CodingKey {
        case totalXP
        case streak
        case lessonsCompleted
        case accuracy
        case wordsMastered
        case dictationsPassed
        case reviewsDone
        case studyMinutes
        case ieltsCompleted
        case perfectLessonRuns
        case dailyGoalStreak
    }

    /// Creates a set of learner stats, defaulting every field to zero.
    ///
    /// - Parameters:
    ///   - totalXP: The lifetime XP total.
    ///   - streak: The current study streak in days.
    ///   - lessonsCompleted: The number of lessons finished.
    ///   - accuracy: The lifetime accuracy in `0...1`.
    ///   - wordsMastered: The number of vocabulary items considered learned.
    ///   - dictationsPassed: The number of dictation exercises answered perfectly.
    ///   - reviewsDone: The number of review sessions completed.
    ///   - studyMinutes: The total time spent studying, in minutes.
    ///   - ieltsCompleted: The number of IELTS modules finished.
    ///   - perfectLessonRuns: The number of flawless lessons.
    ///   - dailyGoalStreak: The number of consecutive days the daily goal was met.
    public init(
        totalXP: Int = 0,
        streak: Int = 0,
        lessonsCompleted: Int = 0,
        accuracy: Double = 0,
        wordsMastered: Int = 0,
        dictationsPassed: Int = 0,
        reviewsDone: Int = 0,
        studyMinutes: Int = 0,
        ieltsCompleted: Int = 0,
        perfectLessonRuns: Int = 0,
        dailyGoalStreak: Int = 0
    ) {
        self.totalXP = totalXP
        self.streak = streak
        self.lessonsCompleted = lessonsCompleted
        self.accuracy = accuracy
        self.wordsMastered = wordsMastered
        self.dictationsPassed = dictationsPassed
        self.reviewsDone = reviewsDone
        self.studyMinutes = studyMinutes
        self.ieltsCompleted = ieltsCompleted
        self.perfectLessonRuns = perfectLessonRuns
        self.dailyGoalStreak = dailyGoalStreak
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalXP = try container.decodeIfPresent(Int.self, forKey: .totalXP) ?? 0
        streak = try container.decodeIfPresent(Int.self, forKey: .streak) ?? 0
        lessonsCompleted = try container.decodeIfPresent(Int.self, forKey: .lessonsCompleted) ?? 0
        accuracy = try container.decodeIfPresent(Double.self, forKey: .accuracy) ?? 0
        wordsMastered = try container.decodeIfPresent(Int.self, forKey: .wordsMastered) ?? 0
        dictationsPassed = try container.decodeIfPresent(Int.self, forKey: .dictationsPassed) ?? 0
        reviewsDone = try container.decodeIfPresent(Int.self, forKey: .reviewsDone) ?? 0
        studyMinutes = try container.decodeIfPresent(Int.self, forKey: .studyMinutes) ?? 0
        ieltsCompleted = try container.decodeIfPresent(Int.self, forKey: .ieltsCompleted) ?? 0
        perfectLessonRuns = try container.decodeIfPresent(Int.self, forKey: .perfectLessonRuns) ?? 0
        dailyGoalStreak = try container.decodeIfPresent(Int.self, forKey: .dailyGoalStreak) ?? 0
    }

    /// Writes every field, using the same keys the decoder tolerates as optional.
    ///
    /// Required because a hand-written `init(from:)` suppresses the compiler's
    /// synthesised `Encodable`, which would otherwise leave this type declaring
    /// `Codable` without providing half the conformance.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(totalXP, forKey: .totalXP)
        try container.encode(streak, forKey: .streak)
        try container.encode(lessonsCompleted, forKey: .lessonsCompleted)
        try container.encode(accuracy, forKey: .accuracy)
        try container.encode(wordsMastered, forKey: .wordsMastered)
        try container.encode(dictationsPassed, forKey: .dictationsPassed)
        try container.encode(reviewsDone, forKey: .reviewsDone)
        try container.encode(studyMinutes, forKey: .studyMinutes)
        try container.encode(ieltsCompleted, forKey: .ieltsCompleted)
        try container.encode(perfectLessonRuns, forKey: .perfectLessonRuns)
        try container.encode(dailyGoalStreak, forKey: .dailyGoalStreak)
    }
}
