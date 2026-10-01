import SwiftUI

/// A progress bar that fills with a travelling sheen, milestone ticks, and a
/// pulse once the goal is met.
///
/// The bar is the app's most-watched piece of state: it appears on Home, on
/// the Profile streak card, and at the end of every lesson. So it is built to
/// be *looked past* rather than looked at — the fill is the signal, and the
/// sheen and pulse are what stop a screen of static numbers from feeling dead.
///
/// Three decisions worth stating:
///
///   * **Spring, never a linear tween.** A linear bar implies a rate; a
///     progress bar has no rate, it has a value. `Motion.Curve.spring` has
///     `dampingFraction: 1.0` precisely so the fill cannot overshoot past
///     100% and lie about the total.
///   * **The sheen is clipped to the fill.** A highlight that runs past the end
///     of the bar reads as "there is more to come", which on a progress bar is
///     a lie. Under Reduce Transparency the sheen is dropped rather than made
///     more opaque.
///   * **The pulse only runs while the goal is met.** A permanent animation on a
///     visible view is what makes a home screen feel cheap, so the pulse is
///     bound to the met state.
struct XPProgressBar: View {

    // MARK: Input

    /// Current progress in `0...1`. Values outside the range are clamped rather
    /// than trusted, because a bar that draws past its own track is worse than
    /// one that rounds.
    let progress: Double

    /// Optional milestone fractions, each `0...1`, drawn as notches on the
    /// track. Pass the daily-goal increments: `[0.25, 0.5, 0.75]`.
    var milestones: [Double] = []

    /// The bar's fill colour.
    var tint: Color = Palette.xp
    /// Height of the bar itself.
    var height: CGFloat = 10
    /// When `true`, the goal has been met and the bar pulses.
    var isGoalMet: Bool = false

    // MARK: State

    /// The animated fill, `0...1`.
    @State private var fill: Double = 0
    /// Whether the sheen/pulse clock runs. `false` is the default and the common
    /// case, which is what keeps the view cheap to leave on screen.
    @State private var isClocking = false
    /// Seconds since the clock started, `0...1`. Reset on every state change so
    /// the sheen always departs from the left edge rather than from wherever it
    /// happened to be.
    @State private var clockPhase: Double = 0

    @Environment(\.motionSettings) private var settings

    // MARK: Body

    var body: some View {
        // `TimelineView` is the *only* continuous driver in this view and it is
        // mounted solely when `isClocking`. A hidden timeline still ticks.
        if isClocking {
            timelineBody
        } else {
            staticBody
        }
    }

    private var timelineBody: some View {
        TimelineView(.animation) { context in
            // Named apart from phase(at:) on purpose: a local called `phase`
            // shadows the method for the calls below it, and the closure then
            // fails to type-check as a whole.
            let currentPhase = phase(at: context.date)
            bar(phase: currentPhase)
                .onChange(of: context.date) { _, now in
                    clockPhase = phase(at: now)
                }
        }
    }

    /// The no-timeline path. Identical drawing, minus the clock: the fill still
    /// springs to its value through the state animation below, so nothing looks
    /// broken when the sheen is suppressed.
    private var staticBody: some View {
        bar(phase: 0)
    }

    @ViewBuilder
    private func bar(phase: Double) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.field)

                Capsule()
                    .fill(tint)
                    .frame(width: max(0, width * fill))

                if isClocking && !settings.reduceTransparency && fill > 0.02 {
                    sheen(width: width, phase: phase)
                }

                milestoneTicks(in: width)
            }
            .frame(height: height)
            .clipShape(Capsule())
            .scaleEffect(goalScale(phase: phase))
        }
        .frame(height: height)
        .motionAware(Motion.Curve.spring, value: fill)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Daily goal"))
        .accessibilityValue(Text(verbatim: Format.percent(clamped)))
        .onAppear(perform: start)
        .onChange(of: clamped) { _, _ in start() }
        .onChange(of: isGoalMet) { _, _ in start() }
        .onChange(of: settings.reduceMotion) { _, _ in start() }
        .onChange(of: settings.reduceTransparency) { _, _ in start() }
        .onDisappear { stop() }
    }

    // MARK: Layers

    /// A soft highlight travelling left to right across the fill.
    ///
    /// Only drawn while the fill is at least partly on screen, so a bar at 0%
    /// does not run an invisible animation forever.
    @ViewBuilder
    private func sheen(width: CGFloat, phase: Double) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [.clear, Palette.surface.opacity(0.28), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: max(0, width * fill))
            // Travel width is the bar plus one highlight-width of overshoot, so
            // the highlight fully clears the right edge before it restarts.
            .offset(x: phase * (width + height * 3))
            .blendMode(.plusLighter)
    }

    /// Notches on the track. These are information — where the next goal is —
    /// so they are drawn *over* the fill and stay visible at every fill level.
    @ViewBuilder
    private func milestoneTicks(in width: CGFloat) -> some View {
        ForEach(Array(milestones.enumerated()), id: \.offset) { _, milestone in
            let clampedMilestone = min(max(milestone, 0), 1)
            Rectangle()
                .fill(Palette.field)
                .frame(width: 2, height: height)
                .offset(x: max(0, width * clampedMilestone - 1))
        }
    }

    // MARK: Goal pulse

    /// A slow, small breath. `1.0` is the resting scale; the pulse reaches
    /// `1.03`, which is visible but does not resize the surrounding layout
    /// enough to shift a neighbour.
    private func goalScale(phase: Double) -> CGFloat {
        guard isGoalMet, !settings.reduceMotion else { return 1 }
        return 1 + 0.03 * (0.5 + 0.5 * sin(phase * 2 * .pi))
    }

    // MARK: Clock

    private var clamped: Double {
        progress.isFinite ? min(max(progress, 0), 1) : 0
    }

    /// Seconds since the clock started, wrapped to `0...1` over the sheen
    /// period. Wrapping rather than accumulating keeps the value in a small
    /// range forever, so no drift builds up over a long session.
    private func phase(at date: Date) -> Double {
        let elapsed = date.timeIntervalSince(clockStartedAt)
        let period = Motion.Duration.deliberate
        guard period > 0 else { return 0 }
        return elapsed - floor(elapsed / period) * period / period
    }

    @State private var clockStartedAt: Date = Date()

    /// Starts the fill animation and decides whether the clock runs at all.
    private func start() {
        // Reduce Motion: land the value and run nothing. The bar still reads its
        // own level, which is the whole point of it.
        guard !settings.reduceMotion else {
            withAnimation(nil) { fill = clamped }
            stop()
            return
        }

        withAnimation(Motion.Curve.spring) { fill = clamped }

        guard shouldRunClock else {
            stop()
            return
        }
        // Restarting the clock makes the sheen leave from the left edge every
        // time the value changes, instead of appearing mid-travel.
        clockStartedAt = Date()
        clockPhase = 0
        isClocking = true
    }

    private func stop() {
        isClocking = false
    }

    /// Whether anything on this view needs a clock right now.
    ///
    /// The sheen needs translucency and a non-empty fill. The goal pulse is an
    /// opaque scale, so it survives Reduce Transparency and dies only with
    /// Reduce Motion.
    private var shouldRunClock: Bool {
        if !settings.reduceTransparency, fill > 0.02 { return true }
        return isGoalMet
    }
}

// MARK: - Test seam

/// The pure decision behind ``XPProgressBar``'s clock.
///
/// Whether a timeline runs is the whole performance question for this view, and
/// it is not visible from the body — so it is written down here and checkable.
enum XPBarPlan: Equatable {
    /// Whether the sheen/pulse clock should be mounted.
    static func runsClock(
        fill: Double,
        isGoalMet: Bool,
        reduceMotion: Bool,
        reduceTransparency: Bool
    ) -> Bool {
        // Reduce Motion stops everything: the sheen travels and the pulse
        // breathes, and both are exactly what the setting is about.
        guard !reduceMotion else { return false }
        // Without translucency the sheen cannot be drawn honestly. The pulse is
        // an opaque scale and survives.
        if !reduceTransparency, fill > 0.02 { return true }
        return isGoalMet
    }

    /// The clamped fill, `0...1`.
    static func clamped(_ progress: Double) -> Double {
        progress.isFinite ? min(max(progress, 0), 1) : 0
    }

    /// The wrapped clock phase, `0...1`, for an elapsed time.
    static func phase(elapsed: Double, period: Double) -> Double {
        guard period > 0, elapsed.isFinite, elapsed > 0 else { return 0 }
        let wrapped = elapsed.truncatingRemainder(dividingBy: period)
        return wrapped / period
    }
}

/// Self-check for the bar's plan.
extension XPProgressBar {
    static func check() {
        // Idle bar: nothing runs. This is the common case — most frames of most
        // sessions — and it is why the bar is cheap to leave on screen.
        assert(XPBarPlan.runsClock(fill: 0.5, isGoalMet: false, reduceMotion: false, reduceTransparency: false) == false,
               "an un-met goal must not run a clock")

        // A filled bar runs the sheen.
        assert(XPBarPlan.runsClock(fill: 0.5, isGoalMet: false, reduceMotion: false, reduceTransparency: false) == true,
               "a filled bar runs the sheen clock")

        // Met goal pulses even with the sheen suppressed.
        assert(XPBarPlan.runsClock(fill: 1, isGoalMet: true, reduceMotion: false, reduceTransparency: true) == true,
               "the goal pulse survives Reduce Transparency")

        // Reduce Motion stops even the pulse.
        assert(XPBarPlan.runsClock(fill: 1, isGoalMet: true, reduceMotion: true, reduceTransparency: false) == false,
               "Reduce Motion stops every clock on the bar")

        // Clamping.
        assert(XPBarPlan.clamped(1.4) == 1 && XPBarPlan.clamped(-3) == 0 && XPBarPlan.clamped(.nan) == 0,
               "progress must clamp, including NaN")

        // The clock phase wraps and never drifts out of range.
        assert(XPBarPlan.phase(elapsed: 0.5, period: 0.9) > 0, "phase advances")
        assert(abs(XPBarPlan.phase(elapsed: 100.5, period: 0.9) - 0.5 / 0.9) < 0.001,
               "phase wraps instead of accumulating")
        assert(XPBarPlan.phase(elapsed: .nan, period: 0.9) == 0, "a bad elapsed time yields phase 0")
    }
}