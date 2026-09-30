import Foundation
import SwiftData
import Testing
import EnglishCore
@testable import EnglishStore

/// Persistence tests for the store the product actually ships.
///
/// Every test uses a fixed clock and a fixed UTC calendar, so nothing here
/// depends on the wall clock or on the machine's time zone. The kill-and-reopen
/// tests point a container at a real file in a temporary directory, drop the
/// store, and open a second container on the same URL — the only honest way to
/// prove data survived, since an in-memory store is destroyed with its process.
@MainActor
@Suite("EnglishStore persistence")
struct EnglishStoreTests {

    // MARK: - Fixtures

    /// A fixed Gregorian calendar in UTC, so "yesterday" is unambiguous.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    /// 2023-11-14T22:13:20Z, an arbitrary but fixed instant.
    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// The day after ``epoch``, in the fixed calendar.
    static let nextDay = calendar.date(byAdding: .day, value: 1, to: epoch) ?? epoch

    /// A fresh temporary on-disk store URL.
    static func makeStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("EnglishStoreTests-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    /// Opens a store on an existing file, with the fixed clock.
    static func openStore(at url: URL, now: Date = epoch) throws -> ProgressStore {
        let configuration = onDiskConfiguration(url: url)
        return try ProgressStore(
            container: ProgressStore.makeContainer(configuration),
            calendar: calendar,
            now: { now }
        )
    }

    /// Builds a graded result without pulling in the whole content library.
    ///
    /// `ExerciseResult` is frozen in `ARCHITECTURE.md` §2, but the engine lane
    /// may name the memberwise initialiser differently; it is isolated here so
    /// a rename is a one-line fix in this file.
    static func result(
        exerciseID: String,
        correct: Bool,
        accuracy: Double = 1.0,
        xp: Int = 10
    ) -> ExerciseResult {
        ExerciseResult(
            exerciseID: exerciseID,
            isCorrect: correct,
            accuracy: accuracy,
            correctAnswer: .text(["goes"]),
            explanation: "Third person singular takes -s.",
            diffs: [],
            xpAwarded: xp
        )
    }

    // MARK: - Schema smoke

    @Test("the schema opens and every model is present")
    func schemaOpens() throws {
        let store = try ProgressStore(inMemory: true)
        // A malformed @Model graph fails at container creation, so reaching this
        // assertion is the actual test.
        #expect(store.topicProgress().isEmpty)
        #expect(store.lessonProgress().isEmpty)
        #expect(store.vocabularyStates().isEmpty)
        #expect(store.unlockedAchievements().isEmpty)
        #expect(store.resumePoint() == nil)
    }

    @Test("a store rejects a container built from an unrelated schema")
    func rejectsForeignSchema() throws {
        let foreign = try makeForeignContainer()
        #expect(throws: ProgressStore.StoreError.self) {
            try ProgressStore(container: foreign)
        }
    }

    // MARK: - Progress survives close/reopen

    @Test("topic progress and learner stats survive close and reopen")
    func progressSurvivesReopen() throws {
        let url = Self.makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try Self.writeSampleActivity(at: url)
        let before = try Self.readSampleSummary(at: url)
        let after = try Self.readSampleSummary(at: url)

        #expect(after.topics == before.topics)
        #expect(after.stats == before.stats)
        #expect(after.stats.totalXP == 40)
        #expect(after.stats.accuracy == 2.0 / 3.0)
        #expect(after.stats.lessonsCompleted == 1)
        #expect(after.topics["tenses"] == 2.0 / 3.0)
    }

    /// Writes attempts and a completion into a store on `url`, then drops it.
    private static func writeSampleActivity(at url: URL) throws {
        let store = try openStore(at: url)
        store.recordAttempt(result(exerciseID: "ex-1", correct: true), topicID: "tenses", lessonID: "l1")
        store.recordAttempt(result(exerciseID: "ex-2", correct: true), topicID: "tenses", lessonID: "l1")
        store.recordAttempt(
            result(exerciseID: "ex-3", correct: false, accuracy: 0.5),
            topicID: "tenses",
            lessonID: "l1"
        )
        store.recordAttempt(result(exerciseID: "ex-4", correct: true), topicID: "gerund", lessonID: "l2")
        store.completeLesson("l1", topicID: "tenses", xp: 40)
    }

    /// Opens a second, independent store on `url` and reads a value summary.
    ///
    /// Summaries use plain value types rather than the live `@Model` objects, so
    /// the comparison is about what was written to disk.
    private static func readSampleSummary(
        at url: URL
    ) throws -> (topics: [String: Double], stats: LearnerStats) {
        let store = try openStore(at: url)
        return (store.topicProgress().mapValues(\.accuracy), store.learnerStats())
    }

    // MARK: - Streak survives close/reopen

    @Test("a streak survives close and reopen, and grows on the next day")
    func streakSurvivesReopen() throws {
        let url = Self.makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let day1 = try openStore(at: url).registerStudy(minutes: 10, xp: 30, kind: .lesson)
        #expect(day1.current == 1)
        #expect(day1.xpToday == 30)

        let reopened = try openStore(at: url).streak()
        #expect(reopened.current == 1)
        #expect(reopened.totalDays == 1)
        #expect(reopened.xpToday == 30)
        #expect(reopened.longest == 1)

        let day2 = try openStore(at: url, now: Self.nextDay)
            .registerStudy(minutes: 10, xp: 10, kind: .practice)
        #expect(day2.current == 2)
        #expect(day2.longest == 2)
        #expect(day2.totalDays == 2)
        #expect(day2.xpToday == 10)
    }

    @Test("a second session on the same day does not extend the streak")
    func sameDayStreakIsIdempotent() throws {
        let store = try ProgressStore(inMemory: true)
        _ = store.registerStudy(minutes: 10, xp: 10, kind: .lesson)
        let second = store.registerStudy(minutes: 5, xp: 20, kind: .lesson)

        #expect(second.current == 1)
        #expect(second.totalDays == 1)
        // XP accumulates within the day even though the streak does not.
        #expect(second.xpToday == 30)
    }

    @Test("a gap day restarts the streak while the longest run survives")
    func gapDayRestartsStreak() throws {
        let url = Self.makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try openStore(at: url).registerStudy(minutes: 10, xp: 10, kind: .lesson)
        _ = try openStore(at: url, now: Self.nextDay)
            .registerStudy(minutes: 10, xp: 10, kind: .lesson)
        #expect(try openStore(at: url, now: Self.nextDay).streak().current == 2)

        let fiveDaysOn = Self.calendar.date(byAdding: .day, value: 5, to: Self.epoch) ?? Self.epoch
        let afterGap = try openStore(at: url, now: fiveDaysOn)
            .registerStudy(minutes: 10, xp: 10, kind: .lesson)
        #expect(afterGap.current == 1)
        #expect(afterGap.longest == 2)
        #expect(afterGap.totalDays == 3)
    }

    @Test("a plain reopen with no study does not reset the streak")
    func reopenWithoutStudyKeepsStreak() throws {
        let url = Self.makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try openStore(at: url).registerStudy(minutes: 10, xp: 30, kind: .lesson)
        for _ in 0..<3 {
            let untouched = try openStore(at: url).streak()
            #expect(untouched.current == 1)
            #expect(untouched.totalDays == 1)
            #expect(untouched.longest == 1)
        }
    }

    // MARK: - Resume point survives close/reopen

    @Test("the resume point survives close and reopen")
    func resumePointSurvivesReopen() throws {
        let url = Self.makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try openStore(at: url).updateLessonProgress(
            lessonID: "tenses-present",
            topicID: "tenses",
            stepIndex: 2,
            lastStepID: "step-video"
        )
        // A later clock, so the ordering under test is unambiguous.
        try openStore(at: url, now: Self.nextDay).updateLessonProgress(
            lessonID: "tenses-past",
            topicID: "tenses",
            stepIndex: 5,
            lastStepID: "step-quiz"
        )

        let resumed = try openStore(at: url, now: Self.nextDay).resumePoint()
        #expect(resumed?.lessonID == "tenses-past")
        #expect(resumed?.stepIndex == 5)
    }

    @Test("there is no resume point when nothing is in progress")
    func resumePointIsNilWhenEmpty() throws {
        let store = try ProgressStore(inMemory: true)
        #expect(store.resumePoint() == nil)
    }

    @Test("a completed lesson is not a resume point")
    func completedLessonIsNotResumable() throws {
        let store = try ProgressStore(inMemory: true)
        store.updateLessonProgress(lessonID: "l1", topicID: "t1", stepIndex: 3, lastStepID: nil)
        #expect(store.resumePoint()?.lessonID == "l1")

        store.completeLesson("l1", topicID: "t1", xp: 40)
        #expect(store.resumePoint() == nil)
    }

    @Test("the most recently touched unfinished lesson wins")
    func resumePointPrefersMostRecent() throws {
        let url = Self.makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try openStore(at: url).updateLessonProgress(
            lessonID: "old", topicID: "t1", stepIndex: 1, lastStepID: nil
        )
        try openStore(at: url, now: Self.nextDay).updateLessonProgress(
            lessonID: "new", topicID: "t1", stepIndex: 4, lastStepID: nil
        )
        #expect(try openStore(at: url, now: Self.nextDay).resumePoint()?.lessonID == "new")
    }

    // MARK: - Bookmarks survive close/reopen

    @Test("a media bookmark position survives close and reopen")
    func bookmarkSurvivesReopen() throws {
        let url = Self.makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try openStore(at: url).bookmark("a-1") == 0)
        try openStore(at: url).saveBookmark("a-1", position: 42.5)

        #expect(try openStore(at: url).bookmark("a-1") == 42.5)

        try openStore(at: url).saveBookmark("a-1", position: 100)
        #expect(try openStore(at: url).bookmark("a-1") == 100)
    }

    @Test("a negative bookmark position is clamped to zero")
    func bookmarkClampsNegative() throws {
        let store = try ProgressStore(inMemory: true)
        store.saveBookmark("a-2", position: -30)
        #expect(store.bookmark("a-2") == 0)
    }

    // MARK: - Notification prefs survive close/reopen

    @Test("notification prefs return all five kinds, including never-set ones")
    func notificationPrefsAreComplete() throws {
        let store = try ProgressStore(inMemory: true)
        let prefs = store.notificationPrefs()

        #expect(prefs.count == 5)
        #expect(Set(prefs.keys) == Set(NotificationKind.allCases))
        for kind in NotificationKind.allCases {
            let pref = prefs[kind]
            #expect(pref?.enabled == false)
            #expect(pref?.hour == 9)
            #expect(pref?.minute == 0)
        }
    }

    @Test("notification prefs survive close and reopen")
    func notificationPrefsSurviveReopen() throws {
        let url = Self.makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try openStore(at: url).setNotificationPref(.dailyReminder, enabled: true, hour: 20, minute: 15)
        try openStore(at: url).setNotificationPref(.ieltsPractice, enabled: true, hour: 7, minute: 5)

        let prefs = try openStore(at: url).notificationPrefs()
        #expect(prefs.count == 5)
        #expect(prefs[.dailyReminder]?.enabled == true)
        #expect(prefs[.dailyReminder]?.hour == 20)
        #expect(prefs[.dailyReminder]?.minute == 15)
        #expect(prefs[.ieltsPractice]?.minute == 5)
        // Untouched kinds still come back with defaults, not missing.
        #expect(prefs[.streakReminder]?.enabled == false)
        #expect(prefs[.streakReminder]?.hour == 9)
    }

    @Test("out-of-range notification times are clamped")
    func notificationTimesAreClamped() throws {
        let store = try ProgressStore(inMemory: true)
        store.setNotificationPref(.vocabularyReview, enabled: true, hour: 99, minute: -5)
        let pref = store.notificationPrefs()[.vocabularyReview]
        #expect(pref?.hour == 23)
        #expect(pref?.minute == 0)
    }

    // MARK: - Vocabulary favourites survive close/reopen

    @Test("a vocabulary favourite toggle survives close and reopen")
    func favouriteSurvivesReopen() throws {
        let url = Self.makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try openStore(at: url).setFavorite("w-achieve", true)
        try openStore(at: url).setFavorite("w-fail", false)

        let states = try openStore(at: url).vocabularyStates()
        #expect(states.count == 2)
        #expect(states["w-achieve"]?.favorite == true)
        #expect(states["w-fail"]?.favorite == false)

        try openStore(at: url).setFavorite("w-achieve", false)
        #expect(try openStore(at: url).vocabularyStates()["w-achieve"]?.favorite == false)
    }

    // MARK: - Review scheduling

    @Test("a correct attempt schedules a review one day out")
    func correctAttemptSchedulesReview() throws {
        let store = try ProgressStore(inMemory: true)
        store.recordAttempt(
            Self.result(exerciseID: "ex-1", correct: true),
            topicID: "tenses",
            lessonID: "l1"
        )

        let due = try #require(store.reviewQueue(on: Self.epoch.addingTimeInterval(3_600)).first)
        #expect(due.id == "exercise:ex-1")
        #expect(due.repetitions == 1)
        #expect(due.intervalDays == 1)
        #expect(due.lastResultCorrect)

        // Not due immediately.
        #expect(store.reviewQueue(on: Self.epoch).isEmpty)
    }

    @Test("a wrong attempt is due again the same day and penalises ease")
    func wrongAttemptLapses() throws {
        let store = try ProgressStore(inMemory: true)
        store.recordAttempt(
            Self.result(exerciseID: "ex-2", correct: true),
            topicID: "tenses",
            lessonID: "l1"
        )
        store.recordAttempt(
            Self.result(exerciseID: "ex-2", correct: false, accuracy: 0.4),
            topicID: "tenses",
            lessonID: "l1"
        )

        let due = try #require(store.reviewQueue(on: Self.epoch).first)
        #expect(due.lapses == 1)
        #expect(due.repetitions == 0)
        #expect(due.ease < 2.5)
        #expect(due.lastResultCorrect == false)
    }

    @Test("the review queue is ordered by due date ascending")
    func reviewQueueIsSorted() throws {
        let store = try ProgressStore(inMemory: true)
        let base = Self.epoch
        store.upsertReview(Self.reviewItem(id: "exercise:c", due: base.addingTimeInterval(300)))
        store.upsertReview(Self.reviewItem(id: "exercise:a", due: base.addingTimeInterval(100)))
        store.upsertReview(Self.reviewItem(id: "exercise:b", due: base.addingTimeInterval(200)))
        store.upsertReview(Self.reviewItem(id: "exercise:later", due: base.addingTimeInterval(9_000)))

        let ids = store.reviewQueue(on: base.addingTimeInterval(1_000)).map(\.id)
        #expect(ids == ["exercise:a", "exercise:b", "exercise:c"])
    }

    @Test("upserting the same item twice does not duplicate it")
    func upsertReviewIsIdempotent() throws {
        let store = try ProgressStore(inMemory: true)
        var item = Self.reviewItem(id: "vocabulary:w-1", due: Self.epoch)
        store.upsertReview(item)
        item.repetitions = 3
        item.intervalDays = 9
        store.upsertReview(item)

        let state = try #require(store.vocabularyStates()["w-1"])
        #expect(state.reviewCount == 3)
        #expect(state.mastery == 9.0 / 21.0)
    }

    // MARK: - Achievements

    @Test("unlocked achievements survive close and reopen and never duplicate")
    func achievementsSurviveReopen() throws {
        let url = Self.makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try openStore(at: url).unlock(["first-lesson", "streak-3"])
        try openStore(at: url).unlock(["first-lesson"])

        let unlocked = try openStore(at: url).unlockedAchievements()
        #expect(unlocked == ["first-lesson", "streak-3"])
    }

    // MARK: - Study sessions and stats

    @Test("registering study accumulates minutes and XP per kind")
    func registerStudyAccumulates() throws {
        let store = try ProgressStore(inMemory: true)
        store.registerStudy(minutes: 10, xp: 20, kind: .lesson)
        store.registerStudy(minutes: 5, xp: 15, kind: .dictation)
        store.registerStudy(minutes: 3, xp: 5, kind: .practice)

        let stats = store.learnerStats()
        #expect(stats.totalXP == 40)
        #expect(stats.studyMinutes == 18)
        #expect(stats.dictationsPassed == 1)
    }

    @Test("today's XP counter resets when the day rolls over")
    func xpTodayResetsNextDay() throws {
        let url = Self.makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try openStore(at: url).registerStudy(minutes: 10, xp: 60, kind: .lesson)
        #expect(first.xpToday == 60)

        let second = try openStore(at: url, now: Self.nextDay)
            .registerStudy(minutes: 10, xp: 10, kind: .lesson)
        #expect(second.xpToday == 10)
    }

    @Test("completing a lesson banks its XP and marks the lesson done")
    func completeLessonBanksXP() throws {
        let store = try ProgressStore(inMemory: true)
        store.completeLesson("l1", topicID: "tenses", xp: 40)
        store.completeLesson("l2", topicID: "tenses", xp: 30)

        let stats = store.learnerStats()
        #expect(stats.lessonsCompleted == 2)
        #expect(stats.totalXP == 70)
        #expect(store.topicProgress()["tenses"]?.completedAt != nil)
    }

    @Test("stats are all zero for a fresh install")
    func freshStatsAreZero() throws {
        let store = try ProgressStore(inMemory: true)
        let stats = store.learnerStats()
        #expect(stats.totalXP == 0)
        #expect(stats.streak == 0)
        #expect(stats.lessonsCompleted == 0)
        #expect(stats.accuracy == 0)
        #expect(stats.wordsMastered == 0)
        #expect(stats.reviewsDone == 0)
        #expect(stats.studyMinutes == 0)
    }

    // MARK: - Helpers

    /// A review item for queue tests.
    private static func reviewItem(id: String, due: Date) -> ReviewItem {
        let source = ReviewItem.Source(rawValue: String(id.split(separator: ":")[0])) ?? .exercise
        let refID = String(id.split(separator: ":")[1])
        return ReviewItem(
            source: source,
            refID: refID,
            ease: 2.5,
            intervalDays: 0,
            repetitions: 0,
            dueDate: due,
            lastResultCorrect: false,
            lapses: 0,
            createdAt: epoch
        )
    }
}

// MARK: - Test-only conveniences

/// Wraps an on-disk configuration so tests read clearly.
private func onDiskConfiguration(url: URL) -> ModelConfiguration {
    ModelConfiguration(url: url, allowsSave: true, cloudKitDatabase: .none)
}

/// A container holding a single unrelated model, to prove the schema check bites.
private func makeForeignContainer() throws -> ModelContainer {
    try ModelContainer(
        for: UnrelatedModel.self,
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
    )
}

/// A model that belongs to no other test.
@Model
private final class UnrelatedModel {
    var note: String = ""
}


