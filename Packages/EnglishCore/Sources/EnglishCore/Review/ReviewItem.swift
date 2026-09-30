import Foundation

/// A single item tracked by the spaced-repetition scheduler.
///
/// Every reviewable thing in the app — an exercise, a vocabulary word, a whole
/// lesson — becomes a `ReviewItem` keyed by the pair ``Source``/``refID``.
public struct ReviewItem: Sendable, Codable, Identifiable, Hashable {

    /// The kind of content a review item was created from.
    ///
    /// The raw value is the `"<source>:<refID>"` prefix of ``ReviewItem/id``.
    public enum Source: String, Codable, Sendable, Hashable, CaseIterable {
        case exercise
        case vocabulary
        case lesson
    }

    /// The stable identity of the item, formed as `"<source>:<refID>"`.
    ///
    /// Computed from ``source`` and ``refID`` so it can never drift out of sync
    /// with the fields it is derived from.
    public var id: String { "\(source.rawValue):\(refID)" }

    /// The kind of content this item reviews.
    public var source: Source

    /// The id of the reviewed object, in the owning collection.
    public var refID: String

    /// The topic the reviewed object belongs to, when it has one.
    public var topicID: String?

    /// The SM-2 ease factor, starting at `2.5` and floored at ``SpacedRepetition/minimumEase``.
    public var ease: Double

    /// The current scheduling interval in whole days, `0` meaning “due today”.
    public var intervalDays: Int

    /// The count of consecutive successful reviews, reset to `0` by a lapse.
    public var repetitions: Int

    /// The instant from which the item is reviewable.
    public var dueDate: Date

    /// Whether the most recent review was answered correctly.
    public var lastResultCorrect: Bool

    /// The number of times the item has been forgotten after being learned.
    public var lapses: Int

    /// The instant the item was first inserted into the queue.
    public var createdAt: Date

    /// Whether the item counts as learned: both ``intervalDays`` and ``repetitions`` clear their thresholds.
    ///
    /// - Complexity: O(1).
    public var isMastered: Bool { intervalDays >= 21 && repetitions >= 4 }

    /// Creates a review item with an explicit schedule state.
    ///
    /// - Parameters:
    ///   - source: The kind of content being reviewed.
    ///   - refID: The id of the reviewed object.
    ///   - topicID: The owning topic, if any.
    ///   - ease: The starting ease factor.
    ///   - intervalDays: The starting interval in days.
    ///   - repetitions: The starting successful-repetition count.
    ///   - dueDate: The instant the item first becomes reviewable.
    ///   - lastResultCorrect: Whether the last review was answered correctly.
    ///   - lapses: The starting lapse count.
    ///   - createdAt: The insertion instant.
    public init(
        source: Source,
        refID: String,
        topicID: String? = nil,
        ease: Double = 2.5,
        intervalDays: Int = 0,
        repetitions: Int = 0,
        dueDate: Date,
        lastResultCorrect: Bool = false,
        lapses: Int = 0,
        createdAt: Date
    ) {
        self.source = source
        self.refID = refID
        self.topicID = topicID
        self.ease = ease
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.dueDate = dueDate
        self.lastResultCorrect = lastResultCorrect
        self.lapses = lapses
        self.createdAt = createdAt
    }
}
