import Foundation

/// Turns correct answers and streak length into XP.
///
/// The engine is pure: the same inputs always produce the same award, so a
/// session can be replayed without double-paying.
public struct XPEngine: Sendable {

    /// The accuracy at or above which the award is multiplied.
    public static let accuracyBonusThreshold: Double = 0.9

    /// The multiplier applied at ``accuracyBonusThreshold`` and above.
    public static let accuracyMultiplier: Double = 1.5

    /// The number of streak days beyond which the bonus stops growing.
    public static let maximumStreakBonusDays: Int = 7

    /// The XP a learner aims for per day.
    public let dailyGoal: Int

    /// Creates an XP engine.
    ///
    /// - Parameter dailyGoal: The daily XP target used by ``isDailyGoalMet(xp:goal:)``.
    public init(dailyGoal: Int = 50) {
        self.dailyGoal = dailyGoal
    }

    /// The XP earned for one graded response.
    ///
    /// A streak adds one XP per consecutive day up to
    /// ``maximumStreakBonusDays``, and an accuracy of at least
    /// ``accuracyBonusThreshold`` multiplies the whole award by
    /// ``accuracyMultiplier``. A wrong answer earns nothing — not even the
    /// streak bonus.
    ///
    /// - Parameters:
    ///   - base: The XP for the response itself; `0` or less means the response was wrong.
    ///   - streakDays: The learner's current streak in days.
    ///   - accuracy: The session accuracy in `0...1`.
    /// - Returns: The rounded XP award.
    /// - Complexity: O(1).
    public func award(base: Int, streakDays: Int, accuracy: Double) -> Int {
        guard base > 0 else { return 0 }
        let bonus = min(max(streakDays, 0), Self.maximumStreakBonusDays)
        let total = Double(base + bonus)
        guard accuracy >= Self.accuracyBonusThreshold else { return base + bonus }
        return Int((total * Self.accuracyMultiplier).rounded())
    }

    /// Whether the earned XP has reached the daily target.
    ///
    /// - Parameters:
    ///   - xp: The XP earned today.
    ///   - goal: The daily target to compare against.
    /// - Returns: `true` once `xp` reaches `goal`.
    /// - Complexity: O(1).
    public func isDailyGoalMet(xp: Int, goal: Int) -> Bool {
        xp >= goal
    }
}
