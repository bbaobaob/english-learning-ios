import Foundation

/// The persisted shape of a learner's study streak.
///
/// The value is a snapshot: creating one does nothing, and only
/// ``StreakCalculator`` produces transitions, so a plain app launch can never
/// decay the streak.
public struct StreakState: Sendable, Codable, Equatable, Hashable {

    /// The length of the current unbroken run of study days.
    public var current: Int

    /// The longest run of study days ever recorded, which never decreases.
    public var longest: Int

    /// The start of the most recent study day in the calculator's calendar and time zone.
    public var lastStudyDay: Date?

    /// The total count of distinct days on which study was registered.
    public var totalDays: Int

    /// The state of a learner who has never studied.
    public static let empty = StreakState()

    /// Creates a streak snapshot.
    ///
    /// - Parameters:
    ///   - current: The length of the current run of study days.
    ///   - longest: The longest run ever recorded.
    ///   - lastStudyDay: The start of the most recent study day.
    ///   - totalDays: The count of distinct study days.
    public init(
        current: Int = 0,
        longest: Int = 0,
        lastStudyDay: Date? = nil,
        totalDays: Int = 0
    ) {
        self.current = current
        self.longest = longest
        self.lastStudyDay = lastStudyDay
        self.totalDays = totalDays
    }
}
