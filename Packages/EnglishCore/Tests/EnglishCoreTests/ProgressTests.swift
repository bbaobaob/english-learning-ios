import Foundation
import Testing

@testable import EnglishCore

// MARK: - Fixtures

private let referenceNow = Date(timeIntervalSince1970: 1_773_576_000) // 2026-03-15 12:00:00 +0000

private let utc = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func calculator(now: Date = referenceNow) -> StreakCalculator {
    StreakCalculator(calendar: utc, now: { now })
}

private func day(_ offset: Int, from base: Date = referenceNow) -> Date {
    utc.date(byAdding: .day, value: offset, to: base)!
}

/// A wall-clock instant in UTC, for boundary tests that must not hang off a reference date.
private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    return utc.date(from: components)!
}

// MARK: - Streak

@Suite("Streak calculator")
struct StreakTests {

    @Test("the first ever study day starts the streak at one")
    func noHistory() {
        let state = calculator().registeringStudy(on: referenceNow, state: .empty)
        #expect(state.current == 1)
        #expect(state.longest == 1)
        #expect(state.totalDays == 1)
        #require(state.lastStudyDay == utc.startOfDay(for: referenceNow))
    }

    @Test("studying twice in one day changes nothing")
    func sameDayTwice() {
        let srs = calculator()
        let first = srs.registeringStudy(on: referenceNow, state: .empty)
        let second = srs.registeringStudy(on: referenceNow.addingTimeInterval(6 * 3_600), state: first)

        #expect(second == first)
        #expect(second.current == 1)
        #expect(second.totalDays == 1)
    }

    @Test("registering study is idempotent however often it repeats in a day")
    func idempotentWithinADay() {
        let srs = calculator()
        var state = StreakState.empty
        for hour in [0, 3, 9, 18, 23] {
            state = srs.registeringStudy(on: day(0).addingTimeInterval(Double(hour) * 3_600), state: state)
        }
        #expect(state.current == 1)
        #expect(state.longest == 1)
        #expect(state.totalDays == 1)
    }

    @Test("the next calendar day extends the streak")
    func consecutiveDay() {
        let srs = calculator()
        let first = srs.registeringStudy(on: referenceNow, state: .empty)
        let second = srs.registeringStudy(on: day(1), state: first)

        #expect(second.current == 2)
        #expect(second.longest == 2)
        #expect(second.totalDays == 2)
    }

    @Test("a run of days builds one unbroken streak")
    func longRun() {
        let srs = calculator()
        let state = srs.state(after: (0...9).map { day($0) }, from: .empty)
        #expect(state.current == 10)
        #expect(state.longest == 10)
        #expect(state.totalDays == 10)
    }

    @Test("a three-day gap restarts the streak at one")
    func gapResets() {
        let srs = calculator()
        var state = srs.state(after: [day(0), day(1), day(2)], from: .empty)
        #expect(state.current == 3)

        state = srs.registeringStudy(on: day(5), state: state)
        #expect(state.current == 1)
        #expect(state.longest == 3) // the best run is remembered
        #expect(state.totalDays == 4)
    }

    @Test("a month boundary is still a consecutive day")
    func monthBoundary() {
        let srs = calculator()
        let feb28 = utcDate(2026, 2, 28)
        let mar1 = utcDate(2026, 3, 1)

        let first = srs.registeringStudy(on: feb28, state: .empty)
        let second = srs.registeringStudy(on: mar1, state: first)

        #expect(utc.component(.month, from: feb28) == 2)
        #expect(utc.component(.day, from: feb28) == 28)
        #expect(utc.component(.month, from: mar1) == 3)
        #expect(utc.component(.day, from: mar1) == 1)
        #expect(second.current == 2)
        #expect(second.totalDays == 2)
    }

    @Test("a year boundary is also consecutive")
    func yearBoundary() {
        let srs = calculator()
        let dec31 = utcDate(2025, 12, 31)
        let jan1 = utcDate(2026, 1, 1)
        let first = srs.registeringStudy(on: dec31, state: .empty)
        let second = srs.registeringStudy(on: jan1, state: first)
        #expect(second.current == 2)
    }

    @Test("longest never decreases")
    func longestNeverDecreases() {
        let srs = calculator()
        var state = srs.state(after: (0...6).map { day($0) }, from: .empty)
        #expect(state.longest == 7)

        state = srs.registeringStudy(on: day(20), state: state)
        #expect(state.current == 1)
        #expect(state.longest == 7)

        state = srs.registeringStudy(on: day(21), state: state)
        #expect(state.current == 2)
        #expect(state.longest == 7)
    }

    @Test("totalDays counts distinct days only")
    func totalDaysCountsDistinctDays() {
        let srs = calculator()
        let state = srs.state(
            after: [day(0), day(0), day(1), day(1), day(1), day(3)],
            from: .empty
        )
        #expect(state.totalDays == 3) // days 0, 1, 3
        #expect(state.current == 1)    // day 3 follows a gap from day 1
    }

    @Test("an existing record keeps its longest run when the first day is added")
    func preExistingLongestSurvives() {
        let srs = calculator()
        let seeded = StreakState(current: 0, longest: 42, lastStudyDay: nil, totalDays: 100)
        let state = srs.registeringStudy(on: referenceNow, state: seeded)
        #expect(state.current == 1)
        #expect(state.longest == 42)
        #expect(state.totalDays == 101)
    }

    @Test("the calendar's zone decides where a day starts")
    func dayBoundariesFollowTheCalendar() {
        let srs = calculator()
        let first = srs.registeringStudy(on: day(0), state: .empty) // 00:00 UTC
        // 23:00 on the same calendar day is still the same study day.
        let second = srs.registeringStudy(on: day(0).addingTimeInterval(23 * 3_600), state: first)
        #expect(second.totalDays == 1)
        #expect(second.current == 1)

        // One hour past midnight UTC is the next study day.
        let third = srs.registeringStudy(on: day(1).addingTimeInterval(3_600), state: second)
        #expect(third.totalDays == 2)
        #expect(third.current == 2)
    }

    @Test("a streak state round-trips through Codable unchanged")
    func codableRoundTrip() throws {
        let state = calculator().state(after: [day(0), day(1), day(2), day(4)], from: .empty)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(StreakState.self, from: data)
        #expect(decoded == state)
        #expect(decoded.current == 1)   // the gap from day 2 to day 4 restarts it
        #expect(decoded.longest == 3)
        #expect(decoded.totalDays == 4)
    }

    @Test("the empty state encodes and decodes as empty")
    func emptyRoundTrip() throws {
        let data = try JSONEncoder().encode(StreakState.empty)
        let decoded = try JSONDecoder().decode(StreakState.self, from: data)
        #expect(decoded == StreakState.empty)
        #expect(decoded.current == 0)
        #expect(decoded.lastStudyDay == nil)
    }

    @Test("dates supplied out of order still produce one answer")
    func unorderedDates() {
        let ordered = calculator().state(after: [day(0), day(1), day(2)], from: .empty)
        let shuffled = calculator().state(after: [day(2), day(0), day(1)], from: .empty)
        #expect(ordered == shuffled)
    }
}

// MARK: - XP

@Suite("XP engine")
struct XPTests {

    private let engine = XPEngine(dailyGoal: 50)

    @Test("a plain answer earns its base value")
    func baseAward() {
        #expect(engine.award(base: 10, streakDays: 0, accuracy: 0.5) == 10)
        #expect(engine.award(base: 20, streakDays: 0, accuracy: 0.0) == 20)
    }

    @Test("a streak adds one XP per day up to a week")
    func streakBonus() {
        #expect(engine.award(base: 10, streakDays: 0, accuracy: 0.5) == 10)
        #expect(engine.award(base: 10, streakDays: 3, accuracy: 0.5) == 13)
        #expect(engine.award(base: 10, streakDays: 7, accuracy: 0.5) == 17)
        #expect(engine.award(base: 10, streakDays: 99, accuracy: 0.5) == 17) // capped at seven days
    }

    @Test("ninety percent accuracy multiplies the award by one and a half")
    func accuracyMultiplier() {
        // below the threshold: 10 base + 4 streak = 14
        #expect(engine.award(base: 10, streakDays: 4, accuracy: 0.89) == 14)
        // exactly at the threshold: round(14 × 1.5) = 21
        #expect(engine.award(base: 10, streakDays: 4, accuracy: 0.9) == 21)
        #expect(engine.award(base: 10, streakDays: 4, accuracy: 1.0) == 21)
        // no streak: round(10 × 1.5) = 15
        #expect(engine.award(base: 10, streakDays: 0, accuracy: 0.95) == 15)
    }

    @Test("a wrong answer earns nothing, not even the streak bonus")
    func wrongAnswerEarnsNothing() {
        #expect(engine.award(base: 0, streakDays: 0, accuracy: 1.0) == 0)
        #expect(engine.award(base: 0, streakDays: 30, accuracy: 1.0) == 0)
        #expect(engine.award(base: -5, streakDays: 3, accuracy: 0.5) == 0)
    }

    @Test("the daily goal is met at the goal and not one short")
    func dailyGoal() {
        #expect(engine.isDailyGoalMet(xp: 50, goal: 50))
        #expect(engine.isDailyGoalMet(xp: 51, goal: 50))
        #expect(engine.isDailyGoalMet(xp: 49, goal: 50) == false)
        #expect(engine.isDailyGoalMet(xp: 0, goal: 0))
    }

    @Test("the default daily goal is fifty")
    func defaultGoal() {
        #expect(XPEngine().dailyGoal == 50)
    }
}

// MARK: - Achievements

@Suite("Achievements")
struct AchievementTests {

    @Test("the catalogue covers every metric with at least one entry")
    func catalogueCoversEveryMetric() {
        let covered = Set(AchievementEngine.catalogue.map(\.metric))
        for metric in Achievement.Metric.allCases {
            #expect(covered.contains(metric))
        }
        #expect(covered.count == Achievement.Metric.allCases.count)
    }

    @Test("the catalogue has at least twelve entries with unique ids")
    func catalogueSize() {
        #expect(AchievementEngine.catalogue.count >= 12)
        let ids = AchievementEngine.catalogue.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("every achievement is fully written and sensibly thresholded")
    func catalogueIsComplete() {
        for achievement in AchievementEngine.catalogue {
            #expect(!achievement.id.isEmpty)
            #expect(!achievement.title.isEmpty)
            #expect(!achievement.detail.isEmpty)
            #expect(!achievement.symbol.isEmpty)
            #expect(achievement.threshold > 0)
        }
    }

    @Test("accuracy thresholds are whole percentage points")
    func accuracyThresholds() throws {
        for achievement in AchievementEngine.catalogue where achievement.metric == .accuracy {
            #expect(achievement.threshold > 0 && achievement.threshold <= 100)
        }
        let eighty = try #require(AchievementEngine.catalogue.first { $0.id == "accuracy-80" })
        #expect(eighty.isUnlocked(by: LearnerStats(accuracy: 0.80)))
        #expect(eighty.isUnlocked(by: LearnerStats(accuracy: 0.79)) == false)
    }

    @Test("evaluate returns only what the stats have newly earned")
    func evaluateReturnsNewOnly() {
        let stats = LearnerStats(
            totalXP: 600,
            streak: 8,
            lessonsCompleted: 12,
            accuracy: 0.97,
            wordsMastered: 30,
            dictationsPassed: 12,
            reviewsDone: 30,
            studyMinutes: 90,
            ieltsCompleted: 1,
            perfectLessonRuns: 2,
            dailyGoalStreak: 4
        )
        let all = AchievementEngine.evaluate(stats: stats, unlocked: [])
        #expect(all.count >= 12)
        // streak-30, xp-5000, lessons-50 and minutes-600 are out of reach here.
        #expect(all.map(\.id).contains("streak-3"))
        #expect(all.map(\.id).contains("streak-7"))
        #expect(all.map(\.id).contains("xp-500"))
        #expect(all.map(\.id).contains("streak-30") == false)
        #expect(all.map(\.id).contains("xp-5000") == false)
        #expect(all.map(\.id).contains("lessons-50") == false)
        #expect(all.map(\.id).contains("minutes-600") == false)
    }

    @Test("evaluate skips achievements that are already unlocked")
    func evaluateSkipsUnlocked() {
        let stats = LearnerStats(totalXP: 600, streak: 8, lessonsCompleted: 12, accuracy: 0.97)
        let earned = AchievementEngine.evaluate(stats: stats, unlocked: [])
        let ids = Set(earned.map(\Achievement.id))

        let secondPass = AchievementEngine.evaluate(stats: stats, unlocked: ids)
        #expect(secondPass.isEmpty)

        let partial = AchievementEngine.evaluate(stats: stats, unlocked: ["streak-3", "xp-500"])
        #expect(partial.count == ids.count - 2)
        #expect(partial.map(\.id).contains("streak-3") == false)
        #expect(partial.map(\.id).contains("xp-500") == false)
    }

    @Test("an achievement is never re-unlocked when stats only grow")
    func neverReUnlocks() {
        let small = LearnerStats(totalXP: 600, streak: 3)
        let firstPass = AchievementEngine.evaluate(stats: small, unlocked: [])
        let unlocked = Set(firstPass.map(\.id))

        let grown = LearnerStats(totalXP: 9_000, streak: 40, lessonsCompleted: 60, accuracy: 0.99)
        let secondPass = AchievementEngine.evaluate(stats: grown, unlocked: unlocked)
        for achievement in secondPass {
            #expect(unlocked.contains(achievement.id) == false)
        }
        #expect(secondPass.map(\.id).contains("xp-5000"))
        #expect(secondPass.map(\.id).contains("streak-30"))
    }

    @Test("a learner with no stats earns nothing")
    func emptyStatsEarnNothing() {
        #expect(AchievementEngine.evaluate(stats: .empty, unlocked: []).isEmpty)
    }

    @Test("learner stats round-trip through Codable")
    func statsRoundTrip() throws {
        let stats = LearnerStats(
            totalXP: 1_234, streak: 5, lessonsCompleted: 7, accuracy: 0.83, wordsMastered: 40,
            dictationsPassed: 11, reviewsDone: 22, studyMinutes: 333, ieltsCompleted: 2,
            perfectLessonRuns: 3, dailyGoalStreak: 4
        )
        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(LearnerStats.self, from: data)
        #expect(decoded == stats)
    }

    @Test("stats saved before the newer metrics were added still decode")
    func statsTolerateMissingKeys() throws {
        let legacy = #"{"totalXP":250,"streak":2,"lessonsCompleted":3,"accuracy":0.5}"#
        let stats = try JSONDecoder().decode(LearnerStats.self, from: Data(legacy.utf8))
        #expect(stats.totalXP == 250)
        #expect(stats.streak == 2)
        #expect(stats.dailyGoalStreak == 0)
        #expect(stats.perfectLessonRuns == 0)
        #expect(stats.studyMinutes == 0)
    }

    @Test("an achievement round-trips through Codable")
    func achievementRoundTrip() throws {
        let achievement = try #require(AchievementEngine.catalogue.first)
        let data = try JSONEncoder().encode(achievement)
        let decoded = try JSONDecoder().decode(Achievement.self, from: data)
        #expect(decoded == achievement)
    }
}
