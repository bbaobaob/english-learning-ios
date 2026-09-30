import Foundation
import SwiftData
import EnglishCore

/// One recorded study session, the raw input to minutes and XP totals.
@Model
public final class StudySessionRecord {

    /// The instant the session began.
    public var startedAt: Date

    /// The instant the session ended.
    public var endedAt: Date

    /// The session length in whole minutes.
    public var minutes: Int

    /// The XP the session earned.
    public var xpEarned: Int

    /// The raw value of `StudyKind`; see the computed ``kind``.
    public var kindRaw: String

    /// The decoded session kind.
    ///
    /// Falls back to ``StudyKind/lesson`` for an unrecognised raw value so a
    /// future app version that adds a case cannot crash an older one.
    ///
    /// - Complexity: O(1).
    public var kind: StudyKind {
        StudyKind(rawValue: kindRaw) ?? .lesson
    }

    /// Creates a study session record.
    ///
    /// - Parameters:
    ///   - startedAt: The session start instant.
    ///   - endedAt: The session end instant.
    ///   - minutes: The session length in minutes.
    ///   - xpEarned: The XP earned.
    ///   - kind: The session kind.
    public init(
        startedAt: Date,
        endedAt: Date,
        minutes: Int,
        xpEarned: Int,
        kind: StudyKind
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.minutes = minutes
        self.xpEarned = xpEarned
        self.kindRaw = kind.rawValue
    }
}

/// The single streak row, mirroring `EnglishCore.StreakState` plus today's XP.
//
// ponytail: singleton by convention, same as `UserProfile` — the store fetches
// the only row and creates it on first use. A unique key is unnecessary while
// `ProgressStore` is the only writer.
@Model
public final class StreakRecord {

    /// The length of the current unbroken run of study days.
    public var current: Int

    /// The longest run of study days ever recorded.
    public var longest: Int

    /// The total count of distinct days on which study was registered.
    public var totalDays: Int

    /// The start of the most recent study day in the store's calendar.
    public var lastStudyDay: Date?

    /// The XP earned so far on `lastStudyDay`; resets when the day rolls over.
    public var xpToday: Int

    /// The learner's daily XP goal.
    public var xpGoal: Int

    /// Creates the streak row.
    ///
    /// - Parameters:
    ///   - current: The current run length.
    ///   - longest: The longest run ever recorded.
    ///   - totalDays: The count of distinct study days.
    ///   - lastStudyDay: The most recent study day, if any.
    ///   - xpToday: The XP earned today.
    ///   - xpGoal: The daily XP goal.
    public init(
        current: Int = 0,
        longest: Int = 0,
        totalDays: Int = 0,
        lastStudyDay: Date? = nil,
        xpToday: Int = 0,
        xpGoal: Int = 50
    ) {
        self.current = current
        self.longest = longest
        self.totalDays = totalDays
        self.lastStudyDay = lastStudyDay
        self.xpToday = xpToday
        self.xpGoal = xpGoal
    }

    /// The streak half of this row as a core snapshot.
    ///
    /// Module-internal: the mapping is needed by `ProgressStore` only.
    var streakState: StreakState {
        StreakState(current: current, longest: longest, lastStudyDay: lastStudyDay, totalDays: totalDays)
    }

    /// Overwrites the schedule half of this row from a core streak snapshot.
    ///
    /// - Parameter state: The snapshot to persist.
    /// - Complexity: O(1).
    func apply(_ state: StreakState) {
        current = state.current
        longest = state.longest
        totalDays = state.totalDays
        lastStudyDay = state.lastStudyDay
    }
}

/// The unlock record of one achievement.
@Model
public final class AchievementState {

    /// The stable achievement id from `AchievementEngine.catalogue`.
    @Attribute(.unique) public var achievementID: String

    /// The instant the achievement was unlocked.
    public var unlockedAt: Date

    /// Progress toward the achievement in `0...1`.
    public var progress: Double

    /// Creates an achievement state row.
    ///
    /// - Parameters:
    ///   - achievementID: The stable achievement id.
    ///   - unlockedAt: The unlock instant.
    ///   - progress: Progress in `0...1`.
    public init(achievementID: String, unlockedAt: Date, progress: Double = 1) {
        self.achievementID = achievementID
        self.unlockedAt = unlockedAt
        self.progress = progress
    }
}

/// The saved playback position of one audio or video clip.
@Model
public final class MediaBookmark {

    /// The stable clip id; unique, so the row upserts by key.
    @Attribute(.unique) public var clipID: String

    /// The resume position in seconds from the start of the clip.
    public var positionSeconds: Double

    /// The instant the position was last written.
    public var updatedAt: Date

    /// Creates a media bookmark.
    ///
    /// - Parameters:
    ///   - clipID: The stable clip id.
    ///   - positionSeconds: The resume position in seconds.
    ///   - updatedAt: The instant of the write.
    public init(clipID: String, positionSeconds: Double, updatedAt: Date) {
        self.clipID = clipID
        self.positionSeconds = positionSeconds
        self.updatedAt = updatedAt
    }
}

/// One notification schedule preference, one row per `NotificationKind`.
@Model
public final class NotificationPref {

    /// The raw value of ``NotificationKind``; unique, so the row upserts by key.
    @Attribute(.unique) public var kind: String

    /// Whether the learner has switched this notification on.
    public var enabled: Bool

    /// The hour of the local delivery time, `0...23`.
    public var hour: Int

    /// The minute of the local delivery time, `0...59`.
    public var minute: Int

    /// Creates a notification preference.
    ///
    /// - Parameters:
    ///   - kind: The raw notification kind.
    ///   - enabled: Whether the notification is on.
    ///   - hour: The delivery hour, `0...23`.
    ///   - minute: The delivery minute, `0...59`.
    public init(kind: String, enabled: Bool = false, hour: Int = 9, minute: Int = 0) {
        self.kind = kind
        self.enabled = enabled
        self.hour = hour
        self.minute = minute
    }
}
