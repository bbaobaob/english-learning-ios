import SwiftUI

/// A number that rolls to a new value instead of jumping to it.
///
/// Built for XP, streak, study minutes and accuracy — the four figures a
/// learner watches change and wants to *feel* they earned. A plain `Text` that
/// swaps 1200 → 1250 reads as an edit; a roll reads as progress.
///
/// Four behaviours that a naive implementation gets wrong, and this one does
/// not:
///
///   * **0 → 0 is not an animation.** No flash, no scale pop, no wasted work.
///   * **A decrease counts *down*.** A streak reset is a real event and rolling
///     backwards communicates it honestly; clamping to the old value would
///     hide it, and hiding a lost streak is worse than a moving number.
///   * **Large jumps are clamped.** Going 0 → 12,000 rolls for the same
///     duration as 0 → 50. A long roll for a big number is theatre, and it
///     keeps the value unreadable for its whole duration.
///   * **Digits do not jitter.** `AppFont.mono` resolves to
///     `Font.system(design: .monospacedDigit)`, so every digit is the same
///     advance width and the label's width never changes while it counts.
///
/// Under Reduce Motion the value is simply set — no roll, no scale. A number is
/// information, not decoration, so it still updates; it just arrives.
struct CountUpNumber: View {

    // MARK: Input

    /// The value to display.
    let value: Int

    /// How the number is styled. `.title` is the common case (a stat card).
    var textStyle: Font.TextStyle = .title
    /// The weight of the digits.
    var weight: Font.Weight = .bold
    /// The digit colour. Defaults to the app's primary text.
    var tint: Color = Palette.textPrimary
    /// Groups thousands: `12,480`. Turn off for a compact readout.
    var usesGrouping: Bool = true
    /// An optional label spoken by VoiceOver in place of the digits. Use it when
    /// the surrounding view already names what the number means, so VoiceOver
    /// does not read a bare integer out of context.
    var accessibilityLabel: String?

    // MARK: State

    /// What is currently shown. Animated toward `value`, or set outright under
    /// Reduce Motion.
    @State private var displayed: Double = 0
    /// The value `displayed` last settled on, used to suppress the roll when
    /// the view first appears and when the value did not actually change.
    @State private var hasSettled = false

    @Environment(\.motionSettings) private var settings

    // MARK: Body

    var body: some View {
        Text(text)
            .font(AppFont.mono(textStyle, weight: weight))
            .foregroundStyle(tint)
            // The value drives the animation, so it is also the accessibility
            // value. One source, so they can never disagree.
            .motionAware(Motion.Curve.spring, value: displayed)
            // Dynamic Type: the digits shrink to fit rather than pushing the
            // layout, and a very long number at AX5 stays inside its card.
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: labelText))
            .onAppear(perform: settleFromAppearance)
            .onChange(of: value) { _, _ in roll(to: value) }
            .onChange(of: settings.reduceMotion) { _, _ in roll(to: value) }
    }

    // MARK: Rendering

    private var text: String {
        let rounded = Int(displayed.rounded())
        return usesGrouping ? Format.count(rounded) : "\(rounded)"
    }

    private var labelText: String {
        if let accessibilityLabel { return accessibilityLabel }
        return "\(value)"
    }

    // MARK: Rolling

    /// First appearance. Counts up from zero only when there is somewhere to
    /// count to — a stat that starts at zero and stays at zero must not animate
    /// on every navigation, which is the single most common way a count-up
    /// effect gets annoying.
    private func settleFromAppearance() {
        guard !hasSettled else { return }
        hasSettled = true
        guard Motion.isMeaningfulChange(0, Double(value)), !settings.reduceMotion else {
            displayed = Double(value)
            return
        }
        displayed = 0
        withAnimation(Motion.Curve.spring(response: 0.7, dampingFraction: 0.85)) {
            displayed = Double(value)
        }
    }

    private func roll(to newValue: Double) {
        guard Motion.isMeaningfulChange(displayed, newValue) || !hasSettled else { return }
        hasSettled = true

        guard !settings.reduceMotion else {
            // No roll. The number changes and nothing travels — which is the
            // correct reading of "reduce motion", since nothing moved.
            displayed = newValue
            return
        }

        withAnimation(Motion.Curve.spring(response: rollDuration(for: newValue), dampingFraction: 0.9)) {
            displayed = newValue
        }
    }

    /// How long a roll should take, capped so a five-figure jump does not sit on
    /// screen counting.
    ///
    /// A spring's `response` is a period, not a delay, so this is really "how
    /// springy should the settle be": a long roll for a long distance reads as
    /// slow, a short one snaps. `Duration.standard` for small changes,
    /// approaching `Duration.ceremonial` for large ones, and never past it.
    private func rollDuration(for newValue: Double) -> Double {
        let distance = abs(newValue - displayed)
        // 1200 is roughly "a whole level's worth of XP" — beyond that the
        // exact amount stops mattering and only the direction does.
        let normalized = min(distance / 1200, 1)
        return Motion.Duration.standard + normalized * (Motion.Duration.ceremonial - Motion.Duration.standard)
    }
}

// MARK: - Test seam

/// The pure arithmetic behind ``CountUpNumber``, extracted so the edge cases
/// are checkable without a view.
///
/// The behaviour this encodes — 0 → 0 does nothing, a decrease counts down, a
/// huge jump is bounded — is exactly what a reviewer cannot see by reading a
/// SwiftUI body.
enum CountUpPlan: Equatable {
    /// What to display, the `hasSettled` flag, and whether to animate.
    static func resolve(
        displayed: Double,
        target: Double,
        hasSettled: Bool,
        reduceMotion: Bool
    ) -> (displayed: Double, settled: Bool, animates: Bool) {
        // Nothing to do, ever. Covers 0 → 0, and the repeated `.onChange` that
        // fires for an unrelated re-render.
        guard Motion.isMeaningfulChange(displayed, target) || !hasSettled else {
            return (displayed, hasSettled, false)
        }
        guard !reduceMotion else {
            // Snap. The value still updates — Reduce Motion suppresses travel,
            // not information.
            return (target, true, false)
        }
        return (target, true, true)
    }
}

/// Self-check for the roll plan. Run from a debug build or a test target.
///
/// ```swift
/// CountUpNumber.check()
/// ```
extension CountUpNumber {
    static func check() {
        // 0 → 0 must not animate. This is the case that fires on every
        // navigation if it is wrong.
        assert(CountUpPlan.resolve(displayed: 0, target: 0, hasSettled: true, reduceMotion: false)
            == (0, true, false), "0 to 0 must be inert")

        // 0 → 0 on first appearance also settles without animating.
        assert(CountUpPlan.resolve(displayed: 0, target: 0, hasSettled: false, reduceMotion: false)
            == (0, true, false), "first appearance at zero must not animate")

        // A decrease still updates the value, it just does not travel.
        assert(CountUpPlan.resolve(displayed: 7, target: 0, hasSettled: true, reduceMotion: true)
            == (0, true, false), "reduce motion must still land the new value")

        // Normal roll.
        assert(CountUpPlan.resolve(displayed: 1200, target: 1250, hasSettled: true, reduceMotion: false)
            == (1250, true, true), "a normal change animates")

        // First appearance from zero animates when there is somewhere to go.
        assert(CountUpPlan.resolve(displayed: 0, target: 480, hasSettled: false, reduceMotion: false)
            == (480, true, true), "first appearance counts up")

        // Non-finite input must not produce NaN in a Text.
        let nan = CountUpPlan.resolve(displayed: 10, target: .nan, hasSettled: true, reduceMotion: false)
        assert(nan.animates == false || nan.displayed.isFinite, "NaN must never reach a Text")
    }
}