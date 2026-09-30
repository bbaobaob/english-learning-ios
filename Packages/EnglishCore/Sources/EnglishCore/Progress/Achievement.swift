import Foundation

/// A badge the learner can earn by reaching a threshold in one tracked metric.
public struct Achievement: Sendable, Identifiable, Codable, Hashable {

    /// The learner metric an achievement is measured against.
    public enum Metric: String, Codable, Sendable, Hashable, CaseIterable {
        case streakDays
        case totalXP
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

    /// The stable, persisted identity of the achievement.
    public let id: String

    /// The short name shown on the badge.
    public let title: String

    /// The one-line explanation of how to earn it.
    public let detail: String

    /// The SF Symbol name drawn on the badge.
    public let symbol: String

    /// The value of ``metric`` at which the achievement unlocks.
    ///
    /// For ``Metric/accuracy`` this is a whole percentage point, not a fraction.
    public let threshold: Int

    /// The metric the achievement is measured against.
    public let metric: Metric

    /// Creates an achievement.
    ///
    /// - Parameters:
    ///   - id: The stable, persisted identity.
    ///   - title: The short name shown on the badge.
    ///   - detail: The one-line explanation of how to earn it.
    ///   - symbol: The SF Symbol name drawn on the badge.
    ///   - threshold: The value of `metric` at which it unlocks.
    ///   - metric: The metric it is measured against.
    public init(
        id: String,
        title: String,
        detail: String,
        symbol: String,
        threshold: Int,
        metric: Metric
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.threshold = threshold
        self.metric = metric
    }

    /// Whether the supplied stats have reached the threshold.
    ///
    /// - Parameter stats: The learner's current totals.
    /// - Returns: `true` once the tracked metric reaches or passes ``threshold``.
    /// - Complexity: O(1).
    public func isUnlocked(by stats: LearnerStats) -> Bool {
        value(in: stats) >= threshold
    }

    /// The tracked metric's current value, with accuracy expressed in whole percentage points.
    ///
    /// - Parameter stats: The learner's current totals.
    /// - Returns: The integer value compared against ``threshold``.
    /// - Complexity: O(1).
    public func value(in stats: LearnerStats) -> Int {
        switch metric {
        case .streakDays: stats.streak
        case .totalXP: stats.totalXP
        case .lessonsCompleted: stats.lessonsCompleted
        case .accuracy: Int((stats.accuracy * 100).rounded())
        case .wordsMastered: stats.wordsMastered
        case .dictationsPassed: stats.dictationsPassed
        case .reviewsDone: stats.reviewsDone
        case .studyMinutes: stats.studyMinutes
        case .ieltsCompleted: stats.ieltsCompleted
        case .perfectLessonRuns: stats.perfectLessonRuns
        case .dailyGoalStreak: stats.dailyGoalStreak
        }
    }
}
