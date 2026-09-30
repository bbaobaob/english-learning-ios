import Foundation

/// Decides which ``Achievement`` values a learner's stats have just earned.
public struct AchievementEngine: Sendable {

    /// Every achievement the app ships with.
    ///
    /// ponytail: a flat constant list — move it to a JSON resource once the
    /// badges need remote copy changes without an app release.
    public static let catalogue: [Achievement] = [
        // Streak
        Achievement(id: "streak-3", title: "On a Roll", detail: "Study three days in a row.", symbol: "flame.fill", threshold: 3, metric: .streakDays),
        Achievement(id: "streak-7", title: "Week Strong", detail: "Study seven days in a row.", symbol: "flame", threshold: 7, metric: .streakDays),
        Achievement(id: "streak-30", title: "Month of Momentum", detail: "Study thirty days in a row.", symbol: "calendar.badge.checkmark", threshold: 30, metric: .streakDays),

        // Total XP
        Achievement(id: "xp-500", title: "Getting Going", detail: "Earn 500 XP in total.", symbol: "bolt.fill", threshold: 500, metric: .totalXP),
        Achievement(id: "xp-5000", title: "Rising Star", detail: "Earn 5,000 XP in total.", symbol: "sparkles", threshold: 5_000, metric: .totalXP),

        // Lessons
        Achievement(id: "lessons-1", title: "First Step", detail: "Finish your first lesson.", symbol: "book.fill", threshold: 1, metric: .lessonsCompleted),
        Achievement(id: "lessons-10", title: "Ten Down", detail: "Finish ten lessons.", symbol: "books.vertical.fill", threshold: 10, metric: .lessonsCompleted),
        Achievement(id: "lessons-50", title: "Course Complete", detail: "Finish fifty lessons.", symbol: "graduationcap.fill", threshold: 50, metric: .lessonsCompleted),

        // Accuracy
        Achievement(id: "accuracy-80", title: "Sharper Than Most", detail: "Reach 80% lifetime accuracy.", symbol: "target", threshold: 80, metric: .accuracy),
        Achievement(id: "accuracy-95", title: "Near Perfect", detail: "Reach 95% lifetime accuracy.", symbol: "scope", threshold: 95, metric: .accuracy),

        // Vocabulary
        Achievement(id: "words-25", title: "Word Hoarder", detail: "Master twenty-five vocabulary items.", symbol: "text.book.closed.fill", threshold: 25, metric: .wordsMastered),
        Achievement(id: "words-100", title: "Lexicon", detail: "Master one hundred vocabulary items.", symbol: "character.book.closed.fill", threshold: 100, metric: .wordsMastered),

        // Dictation
        Achievement(id: "dictations-10", title: "Trained Ear", detail: "Pass ten dictation exercises.", symbol: "ear.fill", threshold: 10, metric: .dictationsPassed),
        Achievement(id: "dictations-50", title: "Golden Ears", detail: "Pass fifty dictation exercises.", symbol: "ear.badge.checkmark", threshold: 50, metric: .dictationsPassed),

        // Reviews
        Achievement(id: "reviews-25", title: "Card Shark", detail: "Complete twenty-five review sessions.", symbol: "arrow.triangle.2.circlepath", threshold: 25, metric: .reviewsDone),
        Achievement(id: "reviews-100", title: "Memory Athlete", detail: "Complete one hundred review sessions.", symbol: "brain.head.profile", threshold: 100, metric: .reviewsDone),

        // Study time
        Achievement(id: "minutes-60", title: "One Hour In", detail: "Study for sixty minutes in total.", symbol: "clock.fill", threshold: 60, metric: .studyMinutes),
        Achievement(id: "minutes-600", title: "Ten Hours Deep", detail: "Study for six hundred minutes in total.", symbol: "hourglass", threshold: 600, metric: .studyMinutes),

        // IELTS
        Achievement(id: "ielts-1", title: "Test Day", detail: "Complete your first IELTS module.", symbol: "checkmark.seal.fill", threshold: 1, metric: .ieltsCompleted),
        Achievement(id: "ielts-4", title: "Band Ready", detail: "Complete all four IELTS modules.", symbol: "globe.americas.fill", threshold: 4, metric: .ieltsCompleted),

        // Perfect runs
        Achievement(id: "perfect-1", title: "Flawless", detail: "Finish a lesson without a single mistake.", symbol: "seal.fill", threshold: 1, metric: .perfectLessonRuns),
        Achievement(id: "perfect-10", title: "Flawless x10", detail: "Finish ten lessons without a single mistake.", symbol: "crown.fill", threshold: 10, metric: .perfectLessonRuns),

        // Daily goal
        Achievement(id: "goal-3", title: "Three Good Days", detail: "Hit the daily XP goal three days in a row.", symbol: "sun.max.fill", threshold: 3, metric: .dailyGoalStreak),
        Achievement(id: "goal-7", title: "Goal Streak Week", detail: "Hit the daily XP goal seven days in a row.", symbol: "calendar.badge.clock", threshold: 7, metric: .dailyGoalStreak)
    ]

    /// The achievements the learner's stats have met but that are not yet in `unlocked`.
    ///
    /// - Parameters:
    ///   - stats: The learner's current totals.
    ///   - unlocked: The ids already awarded.
    /// - Returns: Only the newly earned achievements, in catalogue order.
    /// - Complexity: O(n) over ``catalogue``.
    public static func evaluate(stats: LearnerStats, unlocked: Set<String>) -> [Achievement] {
        catalogue.filter { !unlocked.contains($0.id) && $0.isUnlocked(by: stats) }
    }
}
