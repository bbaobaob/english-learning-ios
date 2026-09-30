import Foundation
import Testing

@testable import EnglishCore

// MARK: - Fixtures

/// Fixed reference instant: 2026-03-15 12:00:00 +0000.
private let referenceNow = Date(timeIntervalSince1970: 1_773_576_000)

private let utc = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func scheduler(at instant: Date = referenceNow) -> SpacedRepetition {
    SpacedRepetition { instant }
}

private func day(_ offset: Int, from base: Date = referenceNow) -> Date {
    utc.date(byAdding: .day, value: offset, to: base)!
}

private func freshItem() -> ReviewItem {
    SpacedRepetition.makeItem(source: .exercise, refID: "ex-basic-past-1", topicID: "tenses", now: referenceNow)
}

// MARK: - Item identity

@Suite("Review item identity")
struct ReviewItemIdentityTests {

    @Test("id is the source and refID joined by a colon")
    func idFormat() {
        let item = freshItem()
        #expect(item.id == "exercise:ex-basic-past-1")
    }

    @Test("makeItem starts at 2.5 ease and is due immediately")
    func makeItemDefaults() {
        let item = freshItem()
        #expect(item.ease == 2.5)
        #expect(item.intervalDays == 0)
        #expect(item.repetitions == 0)
        #expect(item.lapses == 0)
        #expect(item.lastResultCorrect == false)
        #expect(item.dueDate == referenceNow)
        #expect(item.createdAt == referenceNow)
        #expect(item.topicID == "tenses")
    }

    @Test("makeItem works for every source")
    func allSources() {
        for source in ReviewItem.Source.allCases {
            let item = SpacedRepetition.makeItem(source: source, refID: "x", topicID: nil, now: referenceNow)
            #expect(item.id == "\(source.rawValue):x")
        }
    }
}

// MARK: - SM-2 lite ladder

@Suite("SM-2 scheduling")
struct SchedulingTests {

    @Test("the first good answer schedules one day out")
    func firstGood() {
        let next = scheduler().schedule(freshItem(), grade: .good)
        #expect(next.intervalDays == 1)
        #expect(next.repetitions == 1)
        #expect(next.ease == 2.5)
        #expect(next.lapses == 0)
        #expect(next.lastResultCorrect == true)
    }

    @Test("the second good answer schedules three days out")
    func secondGood() {
        let srs = scheduler()
        let second = srs.schedule(srs.schedule(freshItem(), grade: .good), grade: .good)
        #expect(second.intervalDays == 3)
        #expect(second.repetitions == 2)
    }

    @Test("the third good answer multiplies the interval by the ease factor")
    func thirdGood() {
        let srs = scheduler()
        let two = srs.schedule(srs.schedule(freshItem(), grade: .good), grade: .good)
        let three = srs.schedule(two, grade: .good)
        // round(3 × 2.5) = 8
        #expect(three.intervalDays == 8)
        #expect(three.repetitions == 3)
    }

    @Test("the fourth good answer compounds the previous interval again")
    func fourthGood() {
        let srs = scheduler()
        var item = freshItem()
        for _ in 0..<4 { item = srs.schedule(item, grade: .good) }
        // round(8 × 2.5) = 20
        #expect(item.intervalDays == 20)
        #expect(item.repetitions == 4)
    }

    @Test("schedule leaves the original item untouched")
    func scheduleIsPure() {
        let original = freshItem()
        _ = scheduler().schedule(original, grade: .easy)
        #expect(original.intervalDays == 0)
        #expect(original.repetitions == 0)
        #expect(original.ease == 2.5)
    }

    @Test("a lapse resets the schedule and records the miss")
    func again() {
        let srs = scheduler()
        let learned = srs.schedule(srs.schedule(freshItem(), grade: .good), grade: .good)
        let lapsed = srs.schedule(learned, grade: .again)

        #expect(lapsed.intervalDays == 0)
        #expect(lapsed.repetitions == 0)
        #expect(lapsed.lapses == 1)
        #expect(lapsed.ease == 2.3)          // 2.5 − 0.2
        #expect(lapsed.lastResultCorrect == false)
        #expect(lapsed.dueDate == referenceNow) // due today
    }

    @Test("a lapsed item restarts the good ladder from one day")
    func againThenGood() {
        let srs = scheduler()
        let lapsed = srs.schedule(freshItem(), grade: .again)
        let recovered = srs.schedule(lapsed, grade: .good)
        #expect(recovered.intervalDays == 1)
        #expect(recovered.repetitions == 1)
        #expect(recovered.lapses == 1)
    }

    @Test("ease never falls below the 1.3 floor")
    func easeFloor() {
        let srs = scheduler()
        var item = freshItem()
        for _ in 0..<10 { item = srs.schedule(item, grade: .again) }
        #expect(item.ease == SpacedRepetition.minimumEase)
        #expect(item.ease == 1.3)
        #expect(item.lapses == 10)

        var hardItem = freshItem()
        for _ in 0..<10 { hardItem = srs.schedule(hardItem, grade: .hard) }
        #expect(hardItem.ease == 1.3)
    }

    @Test("hard grows the interval by 20% without crediting a repetition")
    func hard() {
        let srs = scheduler()
        var item = freshItem()
        item = srs.schedule(item, grade: .good) // 1 day
        let hard = srs.schedule(item, grade: .hard)

        #expect(hard.intervalDays == 1)   // max(1, round(1 × 1.2))
        #expect(hard.repetitions == 1)    // hard does not increment
        #expect(hard.ease == 2.35)        // 2.5 − 0.15
        #expect(hard.lastResultCorrect == true)
    }

    @Test("hard compounds on a longer interval")
    func hardCompounds() {
        let srs = scheduler()
        var item = freshItem()
        for _ in 0..<3 { item = srs.schedule(item, grade: .good) } // 8 days
        let hard = srs.schedule(item, grade: .hard)
        #expect(hard.intervalDays == 10) // round(8 × 1.2) = 10
        #expect(hard.ease == 2.35)
    }

    @Test("easy follows the good ladder and raises the ease factor")
    func easy() {
        let srs = scheduler()
        let first = srs.schedule(freshItem(), grade: .easy)
        #expect(first.intervalDays == 1)
        #expect(first.repetitions == 1)
        #expect(first.ease == 2.65) // 2.5 + 0.15

        let second = srs.schedule(first, grade: .easy)
        #expect(second.intervalDays == 3)
        #expect(second.ease == 2.8)
    }

    @Test("easy raises the ease the next good answer multiplies by")
    func easyThenGood() {
        let srs = scheduler()
        let easyFirst = srs.schedule(freshItem(), grade: .easy)
        let easySecond = srs.schedule(easyFirst, grade: .easy)
        let good = srs.schedule(easySecond, grade: .good)
        // round(3 × 2.8) = 8
        #expect(good.intervalDays == 8)
        #expect(good.repetitions == 3)
    }

    @Test("the interval is capped at 180 days")
    func intervalCap() {
        let srs = scheduler()
        var item = freshItem()
        for _ in 0..<12 { item = srs.schedule(item, grade: .easy) }
        #expect(item.intervalDays == SpacedRepetition.maximumIntervalDays)
        #expect(item.intervalDays == 180)
    }

    @Test("grades keep their SM-2 raw values")
    func gradeRawValues() {
        #expect(SpacedRepetition.Grade.again.rawValue == 0)
        #expect(SpacedRepetition.Grade.hard.rawValue == 3)
        #expect(SpacedRepetition.Grade.good.rawValue == 4)
        #expect(SpacedRepetition.Grade.easy.rawValue == 5)
    }

    @Test("the due date lands a whole number of calendar days out")
    func dueDatePlacement() {
        let srs = scheduler()
        let next = srs.schedule(freshItem(), grade: .good)
        // Mirrors the scheduler's own calendar so the assertion holds in any time zone.
        let expected = Calendar.current.date(byAdding: .day, value: 1, to: referenceNow)!
        #expect(next.dueDate == expected)
    }

    @Test("an item round-trips through Codable")
    func codableRoundTrip() throws {
        let item = scheduler().schedule(freshItem(), grade: .good)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ReviewItem.self, from: data)
        #expect(decoded == item)
        #expect(decoded.id == item.id)
    }
}

// MARK: - Due dates

@Suite("Due dates")
struct DueDateTests {

    @Test("an item is due exactly on its due date and after")
    func dueBoundary() {
        let srs = scheduler()
        let item = srs.schedule(freshItem(), grade: .good) // due +1 day
        #expect(srs.isDue(item, on: item.dueDate))
        #expect(srs.isDue(item, on: item.dueDate.addingTimeInterval(1)))
        #expect(srs.isDue(item, on: day(5)))
    }

    @Test("an item is not due before its due date")
    func notDueYet() {
        let srs = scheduler()
        let item = srs.schedule(freshItem(), grade: .good)
        #expect(srs.isDue(item, on: referenceNow) == false)
        #expect(srs.isDue(item, on: item.dueDate.addingTimeInterval(-1)) == false)
    }

    @Test("a newly inserted item is due immediately")
    func newItemsAreDue() {
        let srs = scheduler()
        #expect(srs.isDue(freshItem(), on: referenceNow))
        #expect(srs.isDue(srs.schedule(freshItem(), grade: .again), on: referenceNow))
    }
}

// MARK: - Mastery and bucketing

@Suite("Review queue")
struct ReviewQueueTests {

    /// One item in every interesting state, built by actually grading it.
    private func sampleQueue(srs: SpacedRepetition, at now: Date) -> ReviewQueue {
        func item(_ id: String) -> ReviewItem {
            SpacedRepetition.makeItem(source: .exercise, refID: id, topicID: "tenses", now: now)
        }

        // New: due now, never answered, so it counts as recently wrong.
        let fresh = item("fresh")

        // Lapsed once, then relearned twice: due in three days, one lapse, last answer correct.
        var wrong = srs.schedule(item("wrong"), grade: .good)
        wrong = srs.schedule(wrong, grade: .again)
        wrong = srs.schedule(wrong, grade: .good)
        wrong = srs.schedule(wrong, grade: .good)

        // Lapsed and not yet recovered: due today, one lapse, last answer wrong.
        var lapsed = srs.schedule(item("lapsed"), grade: .good)
        lapsed = srs.schedule(lapsed, grade: .again)

        // Mastered: four good answers, interval above 21.
        var mastered = item("mastered")
        for _ in 0..<4 { mastered = srs.schedule(mastered, grade: .good) }

        return ReviewQueue([fresh, wrong, lapsed, mastered])
    }

    @Test("an item is mastered only past both thresholds")
    func masteryThresholds() {
        var item = freshItem()
        let srs = scheduler()

        for _ in 0..<3 { item = srs.schedule(item, grade: .good) }
        #expect(item.repetitions == 3)
        #expect(item.intervalDays == 8)
        #expect(item.isMastered == false) // needs four repetitions

        item = srs.schedule(item, grade: .good)
        #expect(item.repetitions == 4)
        #expect(item.isMastered == false) // interval still below 21 days

        for _ in 0..<2 { item = srs.schedule(item, grade: .good) }
        #expect(item.intervalDays >= 21)
        #expect(item.isMastered)
    }

    @Test("a lapse un-masters an item")
    func lapseUnmasters() {
        let srs = scheduler()
        var item = freshItem()
        for _ in 0..<6 { item = srs.schedule(item, grade: .good) }
        #expect(item.isMastered)
        let lapsed = srs.schedule(item, grade: .again)
        #expect(lapsed.isMastered == false)
    }

    @Test("dueToday returns exactly the items whose due date has arrived")
    func dueToday() {
        let srs = scheduler()
        let queue = sampleQueue(srs: srs, at: referenceNow)
        let due = queue.dueToday(on: referenceNow)

        #expect(due.map(\.refID) == ["fresh", "lapsed"])
        for item in queue.items {
            #expect(queue.dueToday(on: item.dueDate).contains { $0.id == item.id })
        }
    }

    @Test("dueToday grows as the clock passes each due date")
    func dueTodayGrows() {
        let srs = scheduler()
        let queue = sampleQueue(srs: srs, at: referenceNow)
        // "fresh" and "lapsed" are due at once; "wrong" was relearned to three days.
        #expect(queue.dueToday(on: day(1)).map(\.refID) == ["fresh", "lapsed"])
        #expect(queue.dueToday(on: day(3)).count == 3)
        // "mastered" has four good answers behind it and waits 20 days.
        #expect(queue.dueToday(on: day(19)).count == 3)
        #expect(queue.dueToday(on: day(20)).count == 4)
    }

    @Test("difficult collects only lapsed items")
    func difficult() {
        let srs = scheduler()
        let queue = sampleQueue(srs: srs, at: referenceNow)
        // Both "wrong" and "lapsed" were forgotten at least once.
        #expect(queue.difficult.map(\.refID) == ["wrong", "lapsed"])
        #expect(queue.difficult.allSatisfy { $0.lapses > 0 })
    }

    @Test("recentlyWrong excludes lapsed and learned items, and honours the limit")
    func recentlyWrong() {
        let srs = scheduler()
        let queue = sampleQueue(srs: srs, at: referenceNow)
        // "fresh" has never been answered; "wrong" and "lapsed" lapsed, so they are
        // filed under difficult; "mastered" is learned.
        #expect(queue.recentlyWrong(limit: 10).map(\.refID) == ["fresh"])
        #expect(queue.recentlyWrong(limit: 0).isEmpty)
        #expect(queue.recentlyWrong(limit: -1).isEmpty)
    }

    @Test("recentlyWrong orders by the most recent wrong answer first")
    func recentlyWrongOrdering() {
        func wrongItem(_ refID: String, dueIn days: Int) -> ReviewItem {
            ReviewItem(
                source: .vocabulary,
                refID: refID,
                topicID: "noun",
                ease: 2.5,
                intervalDays: days,
                repetitions: 2,
                dueDate: day(days),
                lastResultCorrect: false,
                lapses: 0,
                createdAt: referenceNow
            )
        }
        let older = wrongItem("older", dueIn: 1)
        let newer = wrongItem("newer", dueIn: 3)
        let queue = ReviewQueue([older, newer])

        #expect(queue.recentlyWrong(limit: 5).map(\.refID) == ["newer", "older"])
        #expect(queue.recentlyWrong(limit: 1).map(\.refID) == ["newer"])
    }

    @Test("mastered collects only learned items")
    func mastered() {
        let srs = scheduler()
        let queue = sampleQueue(srs: srs, at: referenceNow)
        #expect(queue.mastered.map(\.refID) == ["mastered"])
        #expect(queue.mastered.allSatisfy { $0.isMastered })
    }

    @Test("the facets never file one item twice")
    func bucketsDoNotOverlap() {
        let srs = scheduler()
        let queue = sampleQueue(srs: srs, at: referenceNow)
        let facets = [queue.difficult, queue.mastered, queue.recentlyWrong(limit: 100)]
        let allIDs = facets.flatMap { $0.map(\.id) }
        #expect(Set(allIDs).count == allIDs.count)
        #expect(allIDs.count == 4) // every item lands in exactly one facet
        #expect(Set(allIDs) == Set(queue.items.map(\.id)))
    }

    @Test("facets only ever name items that are in the queue")
    func bucketsStayInsideTheQueue() {
        let srs = scheduler()
        let queue = sampleQueue(srs: srs, at: referenceNow)

        // Only the items due right now are actionable at the reference instant.
        let due = queue.dueToday(on: referenceNow)
        #expect(due.map(\.refID) == ["fresh", "lapsed"])
        #expect(Set(due.map(\.id)).count == due.count) // no duplicates in a bucket

        // Far enough out that every item has come due.
        #expect(queue.dueToday(on: day(400)).count == 4)

        let facetIDs = [queue.difficult, queue.mastered, queue.recentlyWrong(limit: 100)]
            .flatMap { $0.map(\.id) }
        #expect(Set(facetIDs).isSubset(of: Set(queue.items.map(\.id))))
    }

    @Test("count and isEmpty describe the queue")
    func queueMetadata() {
        #expect(ReviewQueue().isEmpty)
        #expect(ReviewQueue().count == 0)
        let queue = ReviewQueue([freshItem()])
        #expect(queue.isEmpty == false)
        #expect(queue.count == 1)
    }
}
