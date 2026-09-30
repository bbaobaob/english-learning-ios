import SwiftUI

// MARK: - Motion tokens
//
// `Motion` is declared in `App/DesignSystem/Tokens.swift` and owns three
// `Animation` constants (`quick`, `standard`, `emphatic`) that the rest of the
// app already calls. This file *extends* that type rather than declaring a
// second one: two `enum Motion` in one target is a redeclaration error, and the
// design-system values are the app's public vocabulary and must stay the
// canonical ones.
//
// What is added here is what the tokens file deliberately left out: named
// durations, named curves, the reduce-motion seam, and the two `View`
// modifiers every effect in this folder applies at its animation site.

extension Motion {

    // MARK: Durations
    //
    // Seconds, not `Animation`s. A duration is needed whenever something is
    // driven by a clock rather than by a state change — a `TimelineView` phase,
    // a particle's lifetime, a keyframe track — and inventing `0.23` at those
    // call sites is how a codebase ends up with six slightly different
    // easings that all look accidental.

    /// Named durations, in seconds.
    enum Duration {
        /// A state change the user can perceive happening. `0.15`.
        static let quick: Double = 0.15
        /// The app's default transition. `0.3`.
        static let standard: Double = 0.3
        /// A deliberate, attention-drawing transition. `0.5`.
        static let deliberate: Double = 0.5
        /// A celebration, or a backdrop's slowest loop. `0.9`.
        static let ceremonial: Double = 0.9
        /// Effectively immediate. Used as the "did this change?" threshold.
        static let instant: Double = 0.001
    }

    // MARK: Curves
    //
    // Curves, not durations. Each is a `static var` so the spring parameters
    // stay in one place and every caller gets the same physics.

    /// The app's animation curves.
    enum Curve {
        /// Symmetric and unfussy. Selection, chips, anything that just changed.
        static var standard: Animation { .easeInOut(duration: Duration.standard) }
        /// Decelerating: enters fast, settles slowly. Anything arriving on
        /// screen, because a result that decelerates reads as *landing*.
        static var decelerate: Animation {
            .easeOut(duration: Duration.standard)
        }
        /// A little overshoot, for something that was pushed rather than
        /// switched. Panels and the celebration bursts.
        static var emphasized: Animation {
            .spring(response: 0.42, dampingFraction: 0.7)
        }
        /// No overshoot at all. Bars, rings, and anything with a numeric value
        /// attached — a progress bar that bounces past 100% is lying.
        static var spring: Animation {
            .spring(response: 0.5, dampingFraction: 1.0)
        }
        /// A bouncier spring for a value that should feel physical, e.g. a
        /// counter landing.
        static var bouncy: Animation {
            .spring(response: 0.4, dampingFraction: 0.62)
        }
        /// Continuous and interruptible. Sheen, shimmer, any looping scroll.
        static var linear: Animation { .linear(duration: Duration.deliberate) }
    }

    // MARK: Reduce motion

    /// The live Reduce Motion flag, read straight from UIKit.
    ///
    /// Prefer `@Environment(\.motionSettings).reduceMotion` inside a view, so a
    /// change made in Settings re-renders the view. This static is for the
    /// handful of places with no environment to hand — a haptic helper, a
    /// non-view type — and for readability at a call site.
    static var isReduceMotionEnabled: Bool { UIAccessibility.isReduceMotionEnabled }

    /// A spring built from named parameters rather than magic numbers.
    ///
    /// - Parameters:
    ///   - response: Roughly the duration of one oscillation. `Duration.standard`
    ///     is the neutral value.
    ///   - dampingFraction: `1` is critically damped (no overshoot); lower
    ///     bounces. Values outside `0...1` are clamped rather than rejected,
    ///     because a slightly wrong feel is better than a crashed screen.
    /// - Returns: The spring, or a near-instant linear animation when Reduce
    ///   Motion is on.
    static func spring(
        response: Double = Duration.standard,
        dampingFraction: Double = 0.82
    ) -> Animation {
        reduced(.spring(response: response, dampingFraction: min(max(dampingFraction, 0), 1)))
    }

    /// Collapses `animation` to something effectively instant when Reduce Motion
    /// is on.
    ///
    /// `0.01` rather than `0` because SwiftUI discards a zero-duration
    /// animation entirely, which turns `.animation(_:value:)` into a no-op and
    /// silently skips the *value update* too. A non-zero, imperceptible
    /// duration lets the new value land without anything travelling.
    ///
    /// Reduce Motion means "do not move things", not "do not update things",
    /// so this preserves the end state rather than cancelling the transition.
    static func reduced(_ animation: Animation) -> Animation {
        isReduceMotionEnabled ? .linear(Duration.instant) : animation
    }
}

// MARK: - View modifiers
//
// Every effect in this folder applies one of these at its animation site rather
// than calling `Motion.reduced` by hand. Two reasons: the hand-call version is
// easy to forget on the *fourth* property modifier of a view, and it reads the
// static UIKit flag, which does not invalidate the view when the user changes
// the setting mid-session.

extension View {

    /// Animates this view with `animation` unless Reduce Motion is on, tracking
    /// `value` through the environment.
    ///
    /// The default behaviour for every effect in `App/Motion`. Use it for
    /// anything that *is* motion — a bar filling, a ring sweeping, a checkmark
    /// drawing itself.
    ///
    /// - Parameters:
    ///   - animation: The animation to use when motion is allowed.
    ///   - value: The value whose change triggers it.
    func motionAware<V: Equatable>(
        _ animation: Animation = Motion.Curve.standard,
        value: V
    ) -> some View {
        modifier(MotionAwareModifier(animation: animation, value: value))
    }

    /// Animates this view with `animation` even under Reduce Motion.
    ///
    /// Reserved for the two things a user still needs to *see* change when they
    /// have asked for less motion: an opacity cross-fade (which does not move
    /// anything) and a numeric value settling (which is a change of digits, not
    /// a change of position). Prefer ``motionAware(_:value:)`` for anything
    /// else — this is a deliberate exception, not a synonym.
    ///
    /// - Parameters:
    ///   - animation: The animation to use.
    ///   - value: The value whose change triggers it.
    func reduceMotionAware<V: Equatable>(
        _ animation: Animation = Motion.Curve.standard,
        value: V
    ) -> some View {
        modifier(MotionAwareModifier(animation: animation, value: value, ignoresReduceMotion: true))
    }
}

/// The shared body of both modifiers. Kept as one type so the two entry points
/// cannot drift in how they read the environment.
private struct MotionAwareModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    /// `false` collapses the animation when Reduce Motion is on; `true` keeps it.
    let ignoresReduceMotion: Bool

    @Environment(\.motionSettings) private var settings

    func body(content: Content) -> some View {
        // `Duration.instant` is a 10ms linear: fast enough to read as "it was
        // already like that", slow enough that SwiftUI still performs the
        // value update rather than dropping it.
        content.animation(
            (ignoresReduceMotion || !settings.reduceMotion) ? animation : .linear(Motion.Duration.instant),
            value: value
        )
    }
}

// MARK: - Shared helpers
//
// Two things every effect here needs and neither `App/Motion`'s callers nor the
// design system should have to remember.

extension Motion {
    /// Whether a value is worth animating at all.
    ///
    /// A roll from 0 to 0, or a bar going from 0.4 to 0.4, is not a change.
    /// Guarding on this is what stops a `.onChange` from firing an animation on
    /// every unrelated re-render.
    static func isMeaningfulChange(_ old: Double, _ new: Double, tolerance: Double = 0.0001) -> Bool {
        old.isFinite && new.isFinite && abs(new - old) > tolerance
    }
}

extension View {
    /// Hides this view from VoiceOver.
    ///
    /// Applied to every purely decorative effect. A `Canvas` is one
    /// accessibility element by default and a burst of particles announces as
    /// gibberish, so decorative effects call this rather than leaving each
    /// caller to remember it.
    func motionDecoration() -> some View {
        accessibilityHidden(true)
    }
}