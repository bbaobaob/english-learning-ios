import Foundation

/// Advances a ``StreakState`` as study days arrive.
///
/// Both the calendar and the clock are injected so a streak never depends on
/// the device's locale, time zone, or the moment the test happens to run.
public struct StreakCalculator: Sendable {

    private let calendar: Calendar
    private let now: @Sendable () -> Date

    /// Creates a calculator.
    ///
    /// - Parameters:
    ///   - calendar: Supplies the day boundaries that separate one study day from the next.
    ///   - now: Supplies the current instant; exposed for callers that need to stamp a study day themselves.
    public init(calendar: Calendar = .current, now: @escaping @Sendable () -> Date = Date.init) {
        self.calendar = calendar
        self.now = now
    }

    /// The current instant according to the injected clock.
    ///
    /// - Complexity: O(1).
    public var currentDate: Date { now() }

    /// Returns the streak after study is registered on a given day.
    ///
    /// The same calendar day is a no-op, the immediately following day extends
    /// the streak, and any earlier day restarts it at one. ``StreakState/totalDays``
    /// only grows on a genuinely new day.
    ///
    /// - Parameters:
    ///   - date: The instant of the study session.
    ///   - state: The streak before this session.
    /// - Returns: A new streak; the argument is never mutated.
    /// - Complexity: O(1).
    public func registeringStudy(on date: Date, state: StreakState) -> StreakState {
        let day = calendar.startOfDay(for: date)
        guard let lastDay = state.lastStudyDay.map({ calendar.startOfDay(for: $0) }) else {
            return StreakState(
                current: 1,
                longest: max(state.longest, 1),
                lastStudyDay: day,
                totalDays: state.totalDays + 1
            )
        }

        if day == lastDay {
            return state
        }

        let gap = calendar.dateComponents([.day], from: lastDay, to: day).day ?? 0
        let current = gap == 1 ? state.current + 1 : 1

        return StreakState(
            current: current,
            longest: max(state.longest, current),
            lastStudyDay: day,
            totalDays: state.totalDays + 1
        )
    }

    /// Folds a batch of study dates into a single streak.
    ///
    /// - Parameters:
    ///   - dates: The study instants, in any order.
    ///   - initial: The streak the batch starts from.
    /// - Returns: The streak after every date in `dates` has been registered.
    /// - Complexity: O(n log n), from the sort.
    public func state(after dates: [Date], from initial: StreakState) -> StreakState {
        // ponytail: sorts the batch so a caller that records out of order still gets one answer;
        // drop the sort and fold in arrival order if the call site is already chronological.
        dates.sorted().reduce(initial) { registeringStudy(on: $1, state: $0) }
    }
}
