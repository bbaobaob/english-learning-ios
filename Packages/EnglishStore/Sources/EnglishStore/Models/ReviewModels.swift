import Foundation
import SwiftData
import EnglishCore

/// The persisted spaced-repetition state of one reviewable item.
///
/// The frozen schema carries no column for `ReviewItem.lastResultCorrect` or
/// `ReviewItem.createdAt`, so both are reconstructed on read (see
/// ``Swift/ReviewState/reviewItem(on:createdAt:)``).
@Model
public final class ReviewState {

    /// The review item id, `"<source>:<refID>"`; unique, so the row upserts by key.
    @Attribute(.unique) public var itemID: String

    /// The instant from which the item is reviewable.
    public var dueDate: Date

    /// The SM-2 ease factor, starting at `2.5`.
    public var ease: Double

    /// The scheduling interval in whole days, `0` meaning due today.
    public var intervalDays: Int

    /// The count of consecutive successful reviews.
    public var repetitions: Int

    /// The count of times the item was forgotten after being learned.
    public var lapses: Int

    /// The raw value of `ReviewItem.Source`.
    public var source: String

    /// The id of the reviewed object in its owning collection.
    public var refID: String

    /// The owning topic id, when the reviewed object has one.
    public var topicID: String?

    /// Creates a persisted review state.
    ///
    /// - Parameters:
    ///   - itemID: The review item id.
    ///   - dueDate: The next reviewable instant.
    ///   - ease: The SM-2 ease factor.
    ///   - intervalDays: The interval in days.
    ///   - repetitions: The successful-repetition count.
    ///   - lapses: The lapse count.
    ///   - source: The raw review source.
    ///   - refID: The reviewed object id.
    ///   - topicID: The owning topic id, if any.
    public init(
        itemID: String,
        dueDate: Date,
        ease: Double = 2.5,
        intervalDays: Int = 0,
        repetitions: Int = 0,
        lapses: Int = 0,
        source: String,
        refID: String,
        topicID: String? = nil
    ) {
        self.itemID = itemID
        self.dueDate = dueDate
        self.ease = ease
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.lapses = lapses
        self.source = source
        self.refID = refID
        self.topicID = topicID
    }
}

/// Per-word study state backing the vocabulary list and the favourites filter.
@Model
public final class VocabState {

    /// The stable word id; unique, so the row upserts by key.
    @Attribute(.unique) public var wordID: String

    /// Whether the learner has starred the word.
    public var favorite: Bool

    /// The number of times the word has been reviewed, successes plus lapses.
    public var reviewCount: Int

    /// The next instant the word should be reviewed.
    public var nextReviewDate: Date?

    /// Mastery in `0...1`, derived as `min(1, intervalDays / 21)`.
    ///
    /// `1.0` is the same threshold `SpacedRepetition` uses to call an item
    /// mastered, so `wordsMastered` in `LearnerStats` stays honest.
    public var mastery: Double

    /// Creates a vocabulary state row.
    ///
    /// - Parameters:
    ///   - wordID: The stable word id.
    ///   - favorite: Whether the word is starred.
    ///   - reviewCount: The review count.
    ///   - nextReviewDate: The next review instant, if scheduled.
    ///   - mastery: Mastery in `0...1`.
    public init(
        wordID: String,
        favorite: Bool = false,
        reviewCount: Int = 0,
        nextReviewDate: Date? = nil,
        mastery: Double = 0
    ) {
        self.wordID = wordID
        self.favorite = favorite
        self.reviewCount = reviewCount
        self.nextReviewDate = nextReviewDate
        self.mastery = mastery
    }
}

extension ReviewState {

    /// Rebuilds the `EnglishCore` value this row was persisted from.
    ///
    /// `lastResultCorrect` and `createdAt` have no column in the frozen schema,
    /// so they are inferred: an item with a repetition or a lapse has been
    /// reviewed, and the due date stands in for creation.
    ///
    /// - Parameter createdAt: The instant to report as the item's creation date.
    /// - Returns: The equivalent review item.
    /// - Complexity: O(1).
    func reviewItem(on createdAt: Date) -> ReviewItem {
        ReviewItem(
            source: ReviewItem.Source(rawValue: source) ?? .exercise,
            refID: refID,
            topicID: topicID,
            ease: ease,
            intervalDays: intervalDays,
            repetitions: repetitions,
            dueDate: dueDate,
            lastResultCorrect: repetitions > 0,
            lapses: lapses,
            createdAt: createdAt
        )
    }

    /// Overwrites this row's schedule from a review item, leaving identity fields alone.
    ///
    /// - Parameter item: The item to persist.
    /// - Complexity: O(1).
    func apply(_ item: ReviewItem) {
        dueDate = item.dueDate
        ease = item.ease
        intervalDays = item.intervalDays
        repetitions = item.repetitions
        lapses = item.lapses
        source = item.source.rawValue
        refID = item.refID
        topicID = item.topicID
    }
}
