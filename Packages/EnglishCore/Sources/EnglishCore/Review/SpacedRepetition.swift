import Foundation

/// The SM-2 lite scheduler for ``ReviewItem`` values.
///
/// The scheduler is pure: ``schedule(_:grade:)`` returns a new item and never
/// mutates its argument, so a caller can keep the previous state for undo.
public struct SpacedRepetition: Sendable {

    /// The four answer-quality grades a reviewer can give.
    ///
    /// Raw values follow the SM-2 quality scale so they can be stored directly.
    public enum Grade: Int, Sendable, Codable {
        case again = 0
        case hard = 3
        case good = 4
        case easy = 5
    }

    /// The lowest ease factor a struggling item may reach.
    public static let minimumEase: Double = 1.3

    /// The longest interval, in days, the scheduler will ever assign.
    public static let maximumIntervalDays: Int = 180

    /// The ease penalty applied by `Grade/again`.
    public static let lapseEasePenalty: Double = 0.2

    /// The ease penalty applied by `Grade/hard`.
    public static let hardEasePenalty: Double = 0.15

    /// The ease bonus applied by `Grade/easy`.
    public static let easyEaseBonus: Double = 0.15

    /// The interval multiplier applied by `Grade/hard`.
    public static let hardIntervalMultiplier: Double = 1.2

    private let now: @Sendable () -> Date

    /// Creates a scheduler.
    ///
    /// - Parameter now: Supplies the “current” instant used to place due dates; injected so tests are deterministic.
    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    /// Builds the first ``ReviewItem`` for a piece of content, due immediately.
    ///
    /// - Parameters:
    ///   - source: The kind of content being reviewed.
    ///   - refID: The id of the reviewed object.
    ///   - topicID: The owning topic, if any.
    ///   - now: The insertion instant, also used as the first due date.
    /// - Returns: A fresh item with `2.5` ease and a zeroed schedule.
    public static func makeItem(
        source: ReviewItem.Source,
        refID: String,
        topicID: String? = nil,
        now: Date
    ) -> ReviewItem {
        ReviewItem(
            source: source,
            refID: refID,
            topicID: topicID,
            ease: 2.5,
            intervalDays: 0,
            repetitions: 0,
            dueDate: now,
            lastResultCorrect: false,
            lapses: 0,
            createdAt: now
        )
    }

    /// Returns the item's next state after being graded, leaving the original untouched.
    ///
    /// `again` collapses the schedule to zero days, resets the repetition count
    /// and lowers the ease factor. `hard` grows the interval by 20% without
    /// crediting a repetition. `good` and `easy` credit a repetition and take
    /// the `1`, `3`, `previous × ease` ladder, capped at
    /// ``maximumIntervalDays``.
    ///
    /// - Parameters:
    ///   - item: The item as it stands before the review.
    ///   - grade: The grade the reviewer gave.
    /// - Returns: A new item carrying the rescheduled state.
    /// - Complexity: O(1).
    public func schedule(_ item: ReviewItem, grade: Grade) -> ReviewItem {
        var next = item
        next.lastResultCorrect = grade != .again

        switch grade {
        case .again:
            next.ease = max(Self.minimumEase, item.ease - Self.lapseEasePenalty)
            next.intervalDays = 0
            next.repetitions = 0
            next.lapses = item.lapses + 1

        case .hard:
            // ponytail: a hard repeat never credits a repetition, so repeated hards sit at one day;
            // revisit the ladder if practice shows the interval should still compound.
            next.ease = max(Self.minimumEase, item.ease - Self.hardEasePenalty)
            next.intervalDays = min(
                Self.maximumIntervalDays,
                max(1, Int((Double(item.intervalDays) * Self.hardIntervalMultiplier).rounded()))
            )

        case .good, .easy:
            if grade == .easy {
                next.ease = item.ease + Self.easyEaseBonus
            }
            next.repetitions = item.repetitions + 1
            switch next.repetitions {
            case 1: next.intervalDays = 1
            case 2: next.intervalDays = 3
            default:
                next.intervalDays = min(
                    Self.maximumIntervalDays,
                    max(1, Int((Double(item.intervalDays) * next.ease).rounded()))
                )
            }
        }

        next.dueDate = Self.dueDate(intervalDays: next.intervalDays, from: now())
        return next
    }

    /// Whether the item is reviewable at the given instant.
    ///
    /// - Parameters:
    ///   - item: The item to test.
    ///   - date: The instant to test against.
    /// - Returns: `true` from ``ReviewItem/dueDate`` onwards, inclusive.
    /// - Complexity: O(1).
    public func isDue(_ item: ReviewItem, on date: Date) -> Bool {
        item.dueDate <= date
    }

    /// Places the due date a whole number of calendar days after `date`.
    ///
    /// ponytail: uses `Calendar.current`, so a device that changes time zone
    /// mid-study may shift a due date by an hour; inject a calendar here if
    /// schedules ever need to be persisted as exact local midnights.
    private static func dueDate(intervalDays: Int, from date: Date) -> Date {
        guard intervalDays > 0 else { return date }
        return Calendar.current.date(byAdding: .day, value: intervalDays, to: date) ?? date
    }
}
