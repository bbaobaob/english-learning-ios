import SwiftUI

/// A skeleton-loading shimmer, for screens that are waiting on content.
///
/// Skeletons are only better than a spinner when the *shape* of what is coming
/// is known, so this is a modifier rather than a bespoke view: callers apply it
/// to the real layout they already have, and the content is drawn as blocks.
/// A learner's library has lesson cards, a topic grid, and a word list; a
/// spinner over all three says only "wait", while skeletons say "this is what
/// you are about to get".
///
/// Four rules:
///
///   * **It never fakes content.** No fake titles, no placeholder text, no lorem
///     bars pretending to be a sentence. Grey blocks only. A skeleton that looks
///     like content is a skeleton that gets read as content by a screen reader.
///   * **Under Reduce Motion it is a static placeholder.** A travelling highlight
///     is exactly the movement the setting excludes. The blocks stay, at the
///     same muted colour, which still communicates "loading".
///   * **Under Reduce Transparency the highlight is dropped** and the blocks are
///     filled with a flat, slightly stronger colour, so they read as solid place
///     holders rather than as translucent ghosts.
///   * **It stops when it is told to.** No internal timer: the caller passes
///     `isActive`, and when it goes false the timeline unmounts.
struct ShimmerModifier: ViewModifier {

    // MARK: Input

    /// Whether the shimmer is running. `false` leaves plain placeholder blocks.
    var isActive: Bool
    /// The placeholder block colour.
    var tint: Color = Palette.field

    // MARK: State

    /// Drives the highlight. Mounted only while running.
    @State private var isAnimating = false
    @State private var startDate: Date = Date()

    @Environment(\.motionSettings) private var settings

    // MARK: Body

    func body(content: Content) -> some View {
        content
            .redacted(reason: .placeholder)
            .overlay {
                if isAnimating {
                    // The travelling highlight. Read the width from a
                    // `GeometryReader` rather than caching it in `@State`: the
                    // read happens during layout, needs no second pass, and
                    // cannot go stale when the content's width changes.
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        TimelineView(.animation) { context in
                            // Two stops of one gradient and no blur: a blur over
                            // a full-screen skeleton is the most expensive thing a
                            // loading state can do.
                            LinearGradient(
                                colors: highlightColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            // The band is a quarter of the width, swept across
                            // one-and-a-half widths so it fully clears on both
                            // sides before it repeats.
                            .frame(width: width * 0.4)
                            .offset(x: phase(at: context.date) * width * 1.5 - width * 0.25)
                            .blendMode(.plusLighter)
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
            .onAppear(perform: start)
            .onChange(of: isActive) { _, _ in start() }
            .onChange(of: settings.reduceMotion) { _, _ in start() }
            .onChange(of: settings.reduceTransparency) { _, _ in start() }
            .onDisappear { isAnimating = false }
            // A skeleton is never content. Whatever it wraps must not be
            // announced, and must not be reachable, while it is a skeleton.
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    // MARK: Clock

    private func start() {
        let shouldAnimate = isActive
            && !settings.reduceMotion
            && !settings.reduceTransparency
        isAnimating = shouldAnimate
        if shouldAnimate {
            // Restart from the left every time, so the highlight always begins
            // where the eye is already looking.
            startDate = Date()
        }
    }

    /// Wrapped sweep position `0...1`. Wrapped rather than accumulating, so a
    /// long library load cannot drift.
    private func phase(at date: Date) -> Double {
        let period: Double = 1.6
        guard period > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(startDate)
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        return elapsed.truncatingRemainder(dividingBy: period) / period
    }

    /// The highlight's two stops. Derived from the tint rather than hard-coded,
    /// so it stays correct in Dark Mode and against the app's accent.
    private var highlightColors: [Color] {
        [tint.opacity(0), Palette.surface.opacity(0.35), tint.opacity(0)]
    }
}

extension View {

    /// Applies the skeleton treatment while `isActive`.
    ///
    /// Wrap the real content, not a hand-built fake of it:
    /// ```swift
    /// LessonCard(lesson)
    ///     .shimmer(isActive: library.isLoading)
    /// ```
    ///
    /// - Parameters:
    ///   - isActive: Whether the shimmer is running.
    ///   - tint: The placeholder block colour. Defaults to `Palette.field`.
    func shimmer(
        isActive: Bool,
        tint: Color = Palette.field
    ) -> some View {
        modifier(ShimmerModifier(isActive: isActive, tint: tint))
    }
}