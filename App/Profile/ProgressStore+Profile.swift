import Foundation
import SwiftData
import EnglishCore
import EnglishStore

// MARK: - Reads the Profile screen needs that ProgressStore does not expose
//
// ponytail: these are thin reads over the container the store already owns.
// They exist because the app is not allowed to touch persistence directly and
// the package API is frozen. When the package grows a real accessor for one of
// these, delete the method here rather than growing the app.

/// One calendar day of study, keyed by the store's start-of-day instant.
struct StudyDay: Hashable, Identifiable {
    let day: Date
    let minutes: Int
    var id: Date { day }
}

/// Raw counts for one day, so accuracy maths stays in the view model.
struct DayAttempts: Hashable {
    let done: Int
    let correct: Int
}

extension ProgressStore {

    /// The store's main context, reached through the public container.
    ///
    /// The package's own `context` helper is internal, so the app opens its own
    /// door rather than widening the package API. The type is left inferred so
    /// no view in this lane ever names it.
    private var profileContext { container.mainContext }

    private func profileSave() {
        try? profileContext.save()
    }

    private func profileNow() -> Date { Date() }

    // MARK: - Profile

    /// The single learner profile row, created on first use.
    ///
    /// - Returns: A live model; mutating it and calling `profileSave()` persists it.
    func profile() -> UserProfile {
        if let existing = try? profileContext.fetch(FetchDescriptor<UserProfile>()), let first = existing.first {
            return first
        }
        let created = UserProfile(name: "Learner", createdAt: profileNow())
        profileContext.insert(created)
        profileSave()
        return created
    }

    /// Saves a new display name, ignoring an empty or whitespace-only one.
    ///
    /// - Parameter name: The name to persist.
    func setProfileName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profile().name = trimmed
        profileSave()
    }

    /// Stamps `onboardedAt`, once.
    ///
    /// The one piece of onboarding state with no store accessor, so it lived in
    /// `AppState.markOnboarded()` — which made the app's central state object the
    *only* writer of a profile field, against a lane that already owns the other
    /// two. It belongs beside ``setProfileName(_:)`` and ``setDailyGoal(_:)``,
    /// where one writer per field is a rule the Profile lane can see.
    ///
    /// Idempotent: a second call is a no-op, so "has onboarded" cannot be
    /// re-answered by a re-tap on the last onboarding step.
    func markOnboarded() {
        let row = profile()
        guard row.onboardedAt == nil else { return }
        row.onboardedAt = profileNow()
        profileSave()
    }

    /// Saves the daily XP goal on both the profile and the streak row.
    ///
    /// The store reads `StreakRecord.xpGoal` for the ring and for
    /// `dailyGoalStreak`, so the two must move together or the dashboard ring
    /// and the streak disagree.
    ///
    /// - Parameter xp: The new goal, clamped to a sane 10...500 range.
    func setDailyGoal(_ xp: Int) {
        let clamped = min(500, max(10, xp))
        profile().dailyGoalXP = clamped
        if let row = try? profileContext.fetch(FetchDescriptor<StreakRecord>()), let first = row.first {
            first.xpGoal = clamped
        } else {
            profileContext.insert(StreakRecord(xpGoal: clamped))
        }
        profileSave()
    }

    // MARK: - Study sessions

    /// Every stored study session, oldest first.
    ///
    /// - Complexity: O(n log n) in the number of session rows.
    func studySessions() -> [StudySessionRecord] {
        let rows = (try? profileContext.fetch(
            FetchDescriptor<StudySessionRecord>(sortBy: [SortDescriptor(\.endedAt, order: .forward)])
        )) ?? []
        return rows
    }

    /// Study time and XP for every day from `start` to `end`, days with no
    /// session included as zeroes so a heat map has no holes.
    ///
    /// - Parameters:
    ///   - start: First day of the range, already normalised to start of day.
    ///   - end: Last day of the range, inclusive.
    /// - Returns: One entry per calendar day in ascending order.
    /// - Complexity: O(n + d) in session rows and days.
    func studyDays(from start: Date, through end: Date) -> [StudyDay] {
        var minutesByDay: [Date: Int] = [:]
        for session in studySessions() {
            minutesByDay[session.endedAt.startOfDay, default: 0] += session.minutes
        }

        var days: [StudyDay] = []
        var cursor = start
        // Bounded so a bad range cannot spin: 400 days covers any two-month
        // window with room to spare.
        var guardCounter = 0
        while cursor <= end, guardCounter < 400 {
            days.append(StudyDay(day: cursor, minutes: minutesByDay[cursor] ?? 0))
            guard let next = cursor.adding(days: 1) else { break }
            cursor = next
            guardCounter += 1
        }
        return days
    }

    // MARK: - Attempts

    /// Attempt counts for one calendar day.
    ///
    /// - Parameter day: Any instant inside the day of interest.
    func attempts(on day: Date) -> DayAttempts {
        let rows = (try? profileContext.fetch(FetchDescriptor<AttemptRecord>())) ?? []
        var done = 0
        var correct = 0
        for row in rows where Calendar.current.isDate(row.createdAt, inSameDayAs: day) {
            done += 1
            if row.isCorrect { correct += 1 }
        }
        return DayAttempts(done: done, correct: correct)
    }

    // MARK: - Achievements

    /// Unlock dates keyed by achievement id.
    func achievementUnlockDates() -> [String: Date] {
        let rows = (try? profileContext.fetch(FetchDescriptor<AchievementState>())) ?? []
        return Dictionary(rows.map { ($0.achievementID, $0.unlockedAt) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Reset

    /// Deletes every stored row and recreates a blank profile.
    ///
    /// Destructive by design: the Profile screen gates this behind a
    /// confirmation alert, and the streak row is recreated empty so the
    /// dashboard renders its brand-new-learner state rather than crashing on a
    /// missing singleton.
    func resetAllProgress() {
        let models: [any PersistentModel.Type] = [
            AttemptRecord.self, TopicProgress.self, LessonProgress.self,
            ReviewState.self, VocabState.self, StudySessionRecord.self,
            StreakRecord.self, AchievementState.self, MediaBookmark.self,
            UserProfile.self
        ]
        for model in models {
            try? profileContext.delete(model: model)
        }
        try? profileContext.save()

        let goal = profile().dailyGoalXP
        profileContext.insert(StreakRecord(xpGoal: goal))
        profileSave()
    }
}

// MARK: - Small date conveniences

extension Date {
    /// Midnight of this calendar day.
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    /// Midnight one day from now.
    var startOfNextDay: Date { adding(days: 1).startOfDay }

    /// This instant shifted by whole days, then clamped to midnight.
    ///
    /// - Parameter days: The offset, which may be negative.
    func adding(days: Int) -> Date {
        let base = Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
        return base
    }
}
