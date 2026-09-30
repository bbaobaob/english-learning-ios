import Foundation

/// The five notification families the app can schedule.
///
/// One preference row exists per case; `ProgressStore.notificationPrefs()`
/// materialises the missing ones so the settings screen never sees a hole.
public enum NotificationKind: String, Codable, CaseIterable, Sendable {
    /// The end-of-day practice reminder.
    case dailyReminder
    /// The spaced-repetition vocabulary nudge.
    case vocabularyReview
    /// The listening practice nudge.
    case listeningPractice
    /// The IELTS practice nudge.
    case ieltsPractice
    /// The "your streak is at risk" nudge.
    case streakReminder
}
