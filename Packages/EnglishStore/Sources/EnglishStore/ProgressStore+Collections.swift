import Foundation
import SwiftData
import EnglishCore

// Streak, review, vocabulary, achievements, stats, media and notifications.
//
// Split out of `ProgressStore.swift` purely to keep one file readable; this is
// still the same type, and a `public extension` keeps every member as visible
// and as testable as if it were declared in the class body.
extension ProgressStore {

    // MARK: - Streak and study time

    /// Records a study session and updates the streak.
    ///
    /// Idempotent for streak purposes: the day arithmetic is delegated to
    /// `StreakCalculator.registeringStudy(on:state:)`, which returns the state
    /// unchanged for a second session on the same calendar day. Today's XP
    /// counter, by contrast, accumulates, because that is what the ring shows.
    ///
    /// - Parameters:
    ///   - minutes: The session length in minutes.
    ///   - xp: The XP earned.
    ///   - kind: What the learner was doing.
    /// - Returns: The updated streak row.
    /// - Complexity: O(n) in the number of session rows.
    public func registerStudy(minutes: Int, xp: Int, kind: StudyKind) -> StreakRecord {
        let ended = now()
        context.insert(
            StudySessionRecord(
                startedAt: ended.addingTimeInterval(-Double(minutes) * 60),
                endedAt: ended,
                minutes: minutes,
                xpEarned: xp,
                kind: kind
            )
        )

        let record = streakRow()
        // Reset today's XP before the day advances, while lastStudyDay is still
        // the previous day.
        if !isSameDay(record.lastStudyDay, ended) { record.xpToday = 0 }
        record.xpToday += xp
        record.apply(streaks.registeringStudy(on: ended, state: record.streakState))
        persist()
        return record
    }

    /// Returns the streak row, creating it on first use.
    ///
    /// - Returns: The single streak row.
    /// - Complexity: O(n) in the number of streak rows, which is one.
    public func streak() -> StreakRecord {
        let record = streakRow()
        persist()
        return record
    }

    // MARK: - Review

    /// Returns the review items due at the given instant, soonest first.
    ///
    /// - Parameter date: The instant to test due dates against.
    /// - Returns: Due items ordered by ascending due date.
    /// - Complexity: O(n log n) in the number of review rows, from the sort.
    public func reviewQueue(on date: Date) -> [ReviewItem] {
        let created = date
        let items = allRows(ReviewState.self).map { $0.reviewItem(on: created) }
        return items
            .filter { repetition.isDue($0, on: date) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    /// Reads one word's persisted schedule, whether or not it is due.
    ///
    /// ``reviewQueue(on:)`` answers "what is due at this instant", which cannot
    /// answer "what is this word's current interval" for a word scheduled
    /// weeks out — and asking it for a far-future date to get one non-due item
    /// is a sentinel that reads as a bug at every call site. The word detail
    /// screen needs exactly that: a word's interval and ease *while* it is still
    /// days away from being asked.
    ///
    /// - Parameter wordID: The `VocabWord.id` to look up.
    /// - Returns: The item, or `nil` when the word has never been scheduled.
    /// - Complexity: O(n) in the number of review rows.
    public func reviewItem(forWordID wordID: String) -> ReviewItem? {
        let row = allRows(ReviewState.self).first {
            $0.source == ReviewItem.Source.vocabulary.rawValue && $0.refID == wordID
        }
        // `createdAt` is not a column; `reviewItem(on:)` infers the rest and uses
        // this only for the created date, which no caller of this method reads.
        return row?.reviewItem(on: row.dueDate)
    }

    /// Inserts or updates the persisted schedule of one review item.
    ///
    /// A vocabulary item also refreshes its `VocabState` row, which is what
    /// makes ``learnerStats()`` report `wordsMastered`.
    ///
    /// - Parameter item: The item to persist.
    /// - Complexity: O(n) in the number of review and vocabulary rows.
    public func upsertReview(_ item: ReviewItem) {
        let row = fetchOrInsert(ReviewState.self, { $0.itemID == item.id }) {
            ReviewState(
                itemID: item.id,
                dueDate: item.dueDate,
                source: item.source.rawValue,
                refID: item.refID,
                topicID: item.topicID
            )
        }
        row.apply(item)

        guard item.source == .vocabulary else {
            persist()
            return
        }
        let word = fetchOrInsert(VocabState.self, { $0.wordID == item.refID }) {
            VocabState(wordID: item.refID)
        }
        word.reviewCount = item.repetitions + item.lapses
        word.nextReviewDate = item.dueDate
        word.mastery = min(1, Double(item.intervalDays) / 21)
        persist()
    }

    // MARK: - Vocabulary

    /// Stars or unstars a vocabulary word.
    ///
    /// - Parameters:
    ///   - wordID: The word to change.
    ///   - isFavorite: The new favourite flag.
    /// - Complexity: O(n) in the number of vocabulary rows.
    public func setFavorite(_ wordID: String, _ isFavorite: Bool) {
        let row = fetchOrInsert(VocabState.self, { $0.wordID == wordID }) {
            VocabState(wordID: wordID)
        }
        row.favorite = isFavorite
        persist()
    }

    /// Returns every vocabulary state row, keyed by word id.
    ///
    /// - Returns: Live models; treat them as read-only outside the store.
    /// - Complexity: O(n) in the number of vocabulary rows.
    public func vocabularyStates() -> [String: VocabState] {
        Dictionary(uniqueKeysWithValues: allRows(VocabState.self).map { ($0.wordID, $0) })
    }

    // MARK: - Achievements

    /// Returns the ids of every unlocked achievement.
    ///
    /// - Complexity: O(n) in the number of achievement rows.
    public func unlockedAchievements() -> Set<String> {
        Set(allRows(AchievementState.self).map(\.achievementID))
    }

    /// Unlocks achievements, ignoring ids that are already unlocked.
    ///
    /// - Parameter ids: The achievement ids to unlock.
    /// - Complexity: O(n) in the number of achievement rows.
    public func unlock(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let existing = Set(allRows(AchievementState.self).map(\.achievementID))
        let instant = now()
        for id in ids where !existing.contains(id) {
            context.insert(AchievementState(achievementID: id, unlockedAt: instant))
        }
        persist()
    }

    // MARK: - Stats

    /// Aggregates the stored rows into the numbers the Home screen shows.
    ///
    /// Each field, and where it comes from:
    /// - `totalXP`: the sum of `xpEarned` over every study session, including
    ///   the zero-minute rows written by ``completeLesson(_:topicID:xp:)``.
    /// - `streak`: `StreakRecord.current`, never recomputed here, so opening
    ///   the app cannot change it.
    /// - `lessonsCompleted`: lesson rows with `completed == true`.
    /// - `accuracy`: correct attempts over total attempts across all topics,
    ///   `0` when nothing has been attempted.
    /// - `wordsMastered`: vocabulary rows at full mastery, i.e. the same
    ///   21-day interval `SpacedRepetition` uses for `isMastered`.
    /// - `dictationsPassed`: registered `StudyKind.dictation` sessions.
    ///   ponytail: a registered session is assumed to contain a passed item;
    ///   per-item pass rates need a kind column on `AttemptRecord`, which the
    ///   frozen schema does not have.
    /// - `reviewsDone`: review rows that have been graded at least once
    ///   (`repetitions > 0 || lapses > 0`).
    /// - `studyMinutes`: the sum of `minutes` over every session.
    /// - `ieltsCompleted`: distinct IELTS topic ids with a recorded attempt.
    ///   ponytail: counts modules touched, not modules finished; a finished
    ///   count needs the content library's lesson lists.
    /// - `dailyGoalStreak`: the run of consecutive calendar days whose summed
    ///   session XP met `StreakRecord.xpGoal`, counted backwards from the most
    ///   recent session day.
    /// - `perfectLessonRuns`: always `0`. The frozen `LessonProgress` schema has
    ///   no per-step correctness column, so a flawless run cannot be detected.
    ///   ponytail: add a `perfect` flag to `LessonProgress` and set it in
    ///   `completeLesson(_:topicID:xp:)` if the badge turns out to matter.
    ///
    /// - Returns: The aggregated statistics.
    /// - Complexity: O(n log n) in the number of session rows, from sorting the
    ///   per-day XP totals behind `dailyGoalStreak`.
    public func learnerStats() -> LearnerStats {
        let topics = allRows(TopicProgress.self)
        let lessons = allRows(LessonProgress.self)
        let sessions = allRows(StudySessionRecord.self)
        let vocab = allRows(VocabState.self)
        let reviews = allRows(ReviewState.self)
        let attempts = allRows(AttemptRecord.self)
        let goal = streakRow().xpGoal

        let done = topics.reduce(0) { $0 + $1.exercisesDone }
        let correct = topics.reduce(0) { $0 + $1.correctCount }
        let ieltsTopics = Set(
            attempts.lazy
                .filter { $0.topicID.hasPrefix("ielts") }
                .map(\.topicID)
        )

        return LearnerStats(
            totalXP: sessions.reduce(0) { $0 + $1.xpEarned },
            streak: streakRow().current,
            lessonsCompleted: lessons.lazy.filter(\.completed).count,
            accuracy: done == 0 ? 0 : Double(correct) / Double(done),
            wordsMastered: vocab.lazy.filter { $0.mastery >= Self.masteryThreshold }.count,
            dictationsPassed: sessions.lazy.filter { $0.kind == .dictation }.count,
            reviewsDone: reviews.lazy.filter { $0.repetitions > 0 || $0.lapses > 0 }.count,
            studyMinutes: sessions.reduce(0) { $0 + $1.minutes },
            ieltsCompleted: ieltsTopics.count,
            perfectLessonRuns: 0,
            dailyGoalStreak: dailyGoalStreak(sessions: sessions, goal: goal)
        )
    }

    // MARK: - Media

    /// Returns the saved playback position of a clip.
    ///
    /// - Parameter clipID: The clip to look up.
    /// - Returns: The position in seconds, or `0` when nothing was saved.
    /// - Complexity: O(n) in the number of bookmark rows.
    public func bookmark(_ clipID: String) -> Double {
        allRows(MediaBookmark.self).first { $0.clipID == clipID }?.positionSeconds ?? 0
    }

    /// Saves the playback position of a clip.
    ///
    /// - Parameters:
    ///   - clipID: The clip to bookmark.
    ///   - position: The position in seconds; negative values are clamped to `0`.
    /// - Complexity: O(n) in the number of bookmark rows.
    public func saveBookmark(_ clipID: String, position: Double) {
        let row = fetchOrInsert(MediaBookmark.self, { $0.clipID == clipID }) {
            MediaBookmark(clipID: clipID, positionSeconds: 0, updatedAt: now())
        }
        row.positionSeconds = max(0, position)
        row.updatedAt = now()
        persist()
    }

    // MARK: - Notifications

    /// Returns one preference row per ``NotificationKind``, defaults included.
    ///
    /// Missing rows are created disabled at 09:00 on first call, so the
    /// settings screen always renders all five.
    ///
    /// - Returns: Live models keyed by kind; treat them as read-only outside
    ///   the store.
    /// - Complexity: O(n), and it writes one row per never-seen kind.
    public func notificationPrefs() -> [NotificationKind: NotificationPref] {
        let rows = allRows(NotificationPref.self)
        var byRaw: [String: NotificationPref] = [:]
        for row in rows { byRaw[row.kind] = row }

        var result: [NotificationKind: NotificationPref] = [:]
        for kind in NotificationKind.allCases {
            if let existing = byRaw[kind.rawValue] {
                result[kind] = existing
            } else {
                let row = NotificationPref(kind: kind.rawValue)
                context.insert(row)
                byRaw[kind.rawValue] = row
                result[kind] = row
            }
        }
        persist()
        return result
    }

    /// Sets the schedule of one notification kind.
    ///
    /// - Parameters:
    ///   - kind: The notification to configure.
    ///   - enabled: Whether it is on.
    ///   - hour: The delivery hour; values outside `0...23` are clamped.
    ///   - minute: The delivery minute; values outside `0...59` are clamped.
    /// - Complexity: O(n) in the number of preference rows.
    public func setNotificationPref(_ kind: NotificationKind, enabled: Bool, hour: Int, minute: Int) {
        let row = fetchOrInsert(NotificationPref.self, { $0.kind == kind.rawValue }) {
            NotificationPref(kind: kind.rawValue)
        }
        row.enabled = enabled
        row.hour = min(23, max(0, hour))
        row.minute = min(59, max(0, minute))
        persist()
    }
}
