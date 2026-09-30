import SwiftUI

/// An animated flame that genuinely reflects the streak, with an ember trail.
///
/// This replaces the static `flame.fill` glyph in ``StreakFlame``. It earns its
/// cost because **the flame's behaviour is the streak's information**:
///
///   * **Below 3 days the flame is barely alive** — dim and guttering. A learner
///     on day 1 has not built a streak and the app should not pretend otherwise.
///     This is the most honest part of the effect.
///   * **From 3 days it has settled** — brighter and steady. A settled flame
///     should not jump around.
///   * **As the streak grows it gets livelier and brighter**, with the ramp
///     capped at 30 days so a 200-day streak is not five times a 4-day one.
///
/// The mapping lives in ``EmberProfile`` as a pure function of the day count, so
/// it is checkable and two screens cannot disagree about what "day 9" looks like.
///
/// **Under Reduce Motion** it renders the flame at its computed intensity as one
/// static shape: the streak is still legible, still coloured by tier, still
/// carries its day count in text, and nothing flickers. Under Reduce
/// Transparency the ember trail is dropped and the flame becomes a flat fill,
/// since a soft glow with no translucency is just a fuzzy edge.
///
/// Decorative, so it is hidden from VoiceOver — an animated flame adds nothing
/// to "Streak: 7 days", which ``StreakFlame``'s label already carries.
struct StreakEmber: View {

    // MARK: Input

    /// Current streak in days. Clamped at `0`.
    var days: Int
    /// `false` dims the flame without hiding it, so a broken streak still reads
    /// as a streak. Matches `StreakFlame`'s contract.
    var isActive: Bool = true
    /// The flame's edge length in points.
    var size: CGFloat = 28

    // MARK: State

    /// Whether the flicker timeline runs. Mounted only when the flame actually
    /// animates; an idle `TimelineView` still ticks.
    @State private var isAnimating = false

    /// Internal rather than private: the drawing lives in
    /// `StreakEmber+Canvas.swift` and needs to read it.
    @Environment(\.motionSettings) var settings

    // MARK: Body

    var body: some View {
        Group {
            if isAnimating {
                TimelineView(.animation) { context in
                    flame(at: context.date)
                }
            } else {
                // Static path: the same drawing with a frozen phase. Under
                // Reduce Motion this is the only path that ever renders.
                flame(at: nil)
            }
        }
        .frame(width: size, height: size)
        .motionDecoration()
        .onAppear(perform: start)
        .onChange(of: days) { _, _ in start() }
        .onChange(of: isActive) { _, _ in start() }
        .onChange(of: settings.reduceMotion) { _, _ in start() }
        .onDisappear { isAnimating = false }
    }

    // MARK: Profile

    /// How lively the flame is for a given streak.
    ///
    /// Three values, all `0...1`, all derived from `days`. Split out so the tier
    /// boundaries are written down rather than scattered through a draw closure.
    struct EmberProfile: Equatable {
        /// Core brightness.
        let intensity: Double
        /// Flicker amplitude.
        let flicker: Double
        /// Ember count for the trail.
        let emberCount: Int

        /// The profile for a streak of `days` days.
        ///
        /// - Parameter days: Streak length; negative values are treated as 0.
        /// - Returns: The profile. Deterministic and total — no input produces a
        ///   value outside `0...1`.
        static func forDays(_ days: Int) -> EmberProfile {
            let clamped = max(days, 0)

            // 0.15 at day 1, 0.5 by day 3, then a slow ramp to a ceiling at 30.
            let settled: Double
            if clamped <= 1 {
                settled = 0.15
            } else if clamped <= 3 {
                settled = 0.15 + 0.35 * Double(clamped - 1) / 2
            } else {
                settled = 0.5 + 0.5 * min(Double(clamped - 3) / 27, 1)
            }

            // Flicker is *inversely* related to confidence up to day 3 — a new
            // flame gutters — then grows slowly again. This is the detail that
            // makes the flame read as reporting a number rather than decorating a
            // label.
            let gutter = clamped <= 3 ? Double(4 - clamped) / 6 : 0
            let ramp = min(Double(clamped) / 30, 1)
            let flicker = min(max(gutter * 0.5 + ramp * 0.35, 0), 0.85)

            // Bounded: at 28pt, more than a handful of embers is unreadable.
            let emberCount = 2 + Int((settled * 8).rounded())

            return EmberProfile(
                intensity: min(max(settled, 0), 1),
                flicker: flicker,
                emberCount: emberCount
            )
        }

        /// The profile for a streak that is not currently active.
        static let inactive = EmberProfile(intensity: 0.08, flicker: 0, emberCount: 0)
    }

    private var profile: EmberProfile {
        isActive ? EmberProfile.forDays(days) : .inactive
    }

    // MARK: Clock

    /// Whether the timeline should run at all. Under Reduce Motion, or for an
    /// inactive streak, nothing animates — which is also what keeps a broken
    /// streak cheap to leave on screen.
    private func start() {
        isAnimating = !settings.reduceMotion && isActive
    }

    /// Wrapped animation time in `0...1`, so it never drifts over a long session
    /// and the flicker stays continuous across a wrap.
    ///
    /// Internal because the drawing in `StreakEmber+Canvas.swift` reads it.
    func time(for date: Date) -> Double {
        let period: Double = 3.1
        guard period > 0 else { return 0 }
        let interval = date.timeIntervalSinceReferenceDate
        guard interval.isFinite else { return 0 }
        return interval.truncatingRemainder(dividingBy: period) / period
    }
}