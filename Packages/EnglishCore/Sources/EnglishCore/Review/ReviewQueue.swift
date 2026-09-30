import Foundation

/// An immutable snapshot of everything waiting to be reviewed.
///
/// ``dueToday(on:)`` is the *actionable* list — the items a session should offer
/// right now. The other three buckets are *facets* used to shape that session
/// (“show me the hard ones”), so they deliberately overlap it: an overdue item
/// with a lapse is both due and difficult. The three facets are mutually
/// exclusive, so an item is never filed under two of them.
public struct ReviewQueue: Sendable {

    /// Every item under review, in insertion order.
    public let items: [ReviewItem]

    /// The number of items in the queue.
    public var count: Int { items.count }

    /// Whether the queue holds no items at all.
    public var isEmpty: Bool { items.isEmpty }

    /// Creates a queue over a set of review items.
    ///
    /// - Parameter items: The items to review, in the order they should be offered.
    public init(_ items: [ReviewItem] = []) {
        self.items = items
    }

    /// The items that are reviewable at the given instant.
    ///
    /// - Parameter date: The instant to test due dates against.
    /// - Returns: Every item whose ``ReviewItem/dueDate`` has arrived or passed.
    /// - Complexity: O(n) over ``items``.
    public func dueToday(on date: Date) -> [ReviewItem] {
        items.filter { $0.dueDate <= date }
    }

    /// The items that have been forgotten at least once since being learned.
    ///
    /// - Complexity: O(n) over ``items``.
    public var difficult: [ReviewItem] {
        items.filter { $0.lapses > 0 }
    }

    /// The items whose most recent review was wrong and which have never lapsed.
    ///
    /// Ordered most recently reviewed first, which — because a wrong answer
    /// resets the interval — is the same as latest ``ReviewItem/dueDate`` first.
    ///
    /// - Parameter limit: The maximum number of items to return; values of zero or less return nothing.
    /// - Returns: Up to `limit` items, newest first.
    /// - Complexity: O(n log n) over ``items``.
    public func recentlyWrong(limit: Int) -> [ReviewItem] {
        guard limit > 0 else { return [] }
        return items
            .filter { !$0.lastResultCorrect && $0.lapses == 0 && !$0.isMastered }
            .sorted { $0.dueDate > $1.dueDate }
            .prefix(limit)
            .map { $0 }
    }

    /// The items that have cleared the learned threshold.
    ///
    /// - Complexity: O(n) over ``items``.
    public var mastered: [ReviewItem] {
        items.filter(\.isMastered)
    }
}
