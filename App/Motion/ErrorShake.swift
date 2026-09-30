import SwiftUI

/// A decaying horizontal shake for a wrong answer, with a static substitute
/// under Reduce Motion.
///
/// A shake is the app's loudest negative signal, so it is deliberately hard to
/// overuse: it fires once per wrong answer, decays over about half a second,
/// and moves by a few points — never enough to push the answer the learner just
/// committed to out of their finger's reach.
///
/// **Under Reduce Motion it does not shake at all.** Not a smaller shake, not a
/// slower one: horizontal movement is precisely what the setting is about, and
/// a shake large enough to be felt is a shake large enough to be a problem for
/// someone who asked the system not to move things.
///
/// So the reduced variant is a **static treatment instead of nothing**: the
/// content gains a `danger` border and an `xmark` badge for the same interval
/// the shake would have run. The learner gets an unmistakable "that was wrong"
/// signal, and it comes from colour *plus a symbol* rather than from movement.
/// The symbol matters — colour alone is never a sufficient signal, which is the
/// same rule `Palette.successSurface` / `Palette.dangerSurface` already follow.
///
/// Pair with ``Haptics/failure()``.
struct ErrorShake<Content: View>: View {

    // MARK: Input

    /// `true` while the wrong-answer treatment should be showing. Bound to the
    /// same result state that shows the `ResultPanel`.
    var isWrong: Bool
    /// Border and badge colour in the reduced variant.
    var tint: Color = Palette.danger
    /// Peak horizontal displacement in points.
    var amplitude: CGFloat = 8
    /// How long the treatment runs, in seconds. Kept short — a long shake feels
    /// punitive.
    var duration: Double = 0.42

    private let content: Content

    // MARK: State

    /// Elapsed seconds since the shake started. `nil` when idle, which keeps the
    /// timeline unmounted for the common case of a screen with nothing wrong.
    @State private var startDate: Date?
    /// `true` once the treatment has finished, so the view stops drawing rather
    /// than leaving an empty timeline running.
    @State private var hasFinished = false
    /// The live clock, sampled only while shaking. This is the value the offset
    /// is read from; when it is `nil` the view is at rest.
    @State private var now: Date = Date()

    @Environment(\.motionSettings) private var settings

    // MARK: Init

    /// - Parameters:
    ///   - isWrong: Whether the wrong-answer treatment is active.
    ///   - tint: Border and badge colour for the reduced variant.
    ///   - amplitude: Peak displacement in points.
    ///   - duration: How long the treatment runs, in seconds.
    ///   - content: The view being treated. Wrap the answer control, so the
    ///     signal lands on the thing that was wrong.
    init(
        isWrong: Bool,
        tint: Color = Palette.danger,
        amplitude: CGFloat = 8,
        duration: Double = 0.42,
        @ViewBuilder content: () -> Content
    ) {
        self.isWrong = isWrong
        self.tint = tint
        self.amplitude = amplitude
        self.duration = duration
        self.content = content()
    }

    // MARK: Body

    var body: some View {
        content
            // The offset is applied unconditionally, and is identically zero
            // under Reduce Motion — that is the whole contract, and it is
            // enforced in one place (``currentOffset``) rather than at the call
            // site where someone could forget the guard.
            .offset(x: currentOffset)
            .overlay { shakeClock }
            .overlay { reducedBorder }
            .overlay(alignment: .topTrailing) { reducedBadge }
            .onAppear(perform: begin)
            .onChange(of: isWrong) { _, _ in begin() }
            .onChange(of: settings.reduceMotion) { _, _ in begin() }
            .onDisappear { startDate = nil }
            // Restarts whenever a wrong answer starts, and is cancelled by
            // SwiftUI on disappear. `isWrong` as the id means a second wrong
            // answer while the first is still shaking does *not* restart it,
            // which is right: a double shake on a double tap is the bug.
            .task(id: isWrong) {
                guard isWrong else { return }
                await clearAfterDelay()
            }
    }

    /// The per-frame clock, mounted **only** while the shake is running, and
    /// drawing nothing at all.
    ///
    /// Its entire job is to advance `now`, which `currentOffset` reads. It is
    /// gated on all four conditions because an idle `TimelineView` still ticks:
    /// an error shake that ran forever behind a static screen would be a battery
    /// bug in the most-used screen in the app.
    @ViewBuilder
    private var shakeClock: some View {
        if !settings.reduceMotion, isWrong, !hasFinished, let start = startDate {
            TimelineView(.animation) { context in
                Color.clear
                    .onChange(of: context.date) { _, date in
                        now = date
                        if date.timeIntervalSince(start) >= duration {
                            hasFinished = true
                            startDate = nil
                        }
                    }
            }
        }
    }

    /// Cancels the treatment after `duration`.
    ///
    /// Attached with `.task(id:)` rather than as an unstructured `Task`, so
    /// SwiftUI cancels it the moment the view disappears or `isWrong` changes —
    /// a task created inside `begin()` would outlive the screen. Under Reduce
    /// Motion this is the *only* clock in the view: its sole job is to hide the
    /// static border and badge when the interval is up.
    private func clearAfterDelay() async {
        try? await Task.sleep(for: .seconds(duration))
        guard !Task.isCancelled else { return }
        hasFinished = true
        startDate = nil
    }

    // MARK: Offset

    /// The horizontal displacement right now.
    private var currentOffset: CGFloat {
        guard let start = startDate, !settings.reduceMotion else { return 0 }
        return Self.offset(
            elapsed: now.timeIntervalSince(start),
            duration: duration,
            amplitude: amplitude,
            reduceMotion: settings.reduceMotion
        )
    }

    /// The displacement as a pure function of elapsed time, so the curve can be
    /// checked without a running animation.
    ///
    /// - Parameters:
    ///   - elapsed: Seconds since the shake began.
    ///   - duration: Total shake length.
    ///   - amplitude: Peak displacement in points.
    ///   - reduceMotion: When `true`, always returns exactly `0`.
    static func offset(
        elapsed: Double,
        duration: Double,
        amplitude: CGFloat,
        reduceMotion: Bool
    ) -> CGFloat {
        // Reduce Motion: no movement at any point, including the first frame.
        guard !reduceMotion, duration > 0, elapsed.isFinite, elapsed >= 0, elapsed < duration else { return 0 }
        let progress = elapsed / duration
        // Three decaying oscillations: `sin` supplies the oscillation, the
        // `(1 - progress)` envelope supplies the decay, and their product is what
        // reads as a physical shake rather than a wobble.
        let envelope = pow(1 - progress, 1.8)
        let oscillation = sin(progress * .pi * 2 * 3)
        return amplitude * envelope * oscillation
    }

    // MARK: Reduced treatment

    /// A static border. Zero movement, full signal.
    @ViewBuilder
    private var reducedBorder: some View {
        if settings.reduceMotion, isWrong, !hasFinished {
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .strokeBorder(tint, lineWidth: 2)
                .allowsHitTesting(false)
        }
    }

    /// A static badge, so the signal is never carried by colour alone.
    @ViewBuilder
    private var reducedBadge: some View {
        if settings.reduceMotion, isWrong, !hasFinished {
            Image(systemName: "xmark")
                AppFont.body(.caption2, weight: .black)
                .foregroundStyle(Palette.surface)
                .padding(3)
                .background(Circle().fill(tint))
                .offset(x: 4, y: -4)
                .allowsHitTesting(false)
        }
    }

    // MARK: Lifecycle

    /// Resets the treatment and starts the shake clock if this is the animated
    /// path. Safe to call repeatedly: `.task(id:)` restarts when the id changes.
    private func begin() {
        hasFinished = false
        now = Date()
        // Under Reduce Motion the shake never runs, so there is nothing to time:
        // the static treatment is bounded by `hasFinished` alone and needs no
        // shake clock.
        startDate = (settings.reduceMotion || !isWrong) ? nil : now
    }
}

// MARK: - Test seam

extension ErrorShake {

    /// Self-check for the shake curve.
    ///
    /// The properties that matter: it starts and ends at rest, never exceeds the
    /// amplitude, stays finite, and is identically zero under Reduce Motion at
    /// every sampled time.
    static func check() {
        let duration = 0.42
        let amplitude: CGFloat = 8
        var peak: CGFloat = 0

        for step in 0...200 {
            let elapsed = Double(step) / 200 * duration
            let value = offset(elapsed: elapsed, duration: duration, amplitude: amplitude, reduceMotion: false)
            assert(value.isFinite, "the shake must stay finite")
            assert(abs(value) <= amplitude + 0.001, "the shake must never exceed its amplitude")
            assert(offset(elapsed: elapsed, duration: duration, amplitude: amplitude, reduceMotion: true) == 0,
                   "Reduce Motion must never move the view")
            if elapsed < duration { peak = max(peak, abs(value)) }
        }

        assert(peak > 0.5, "the shake must actually be visible when it is allowed")
        assert(offset(elapsed: 0, duration: duration, amplitude: amplitude, reduceMotion: false) == 0,
               "the shake starts at rest")
        assert(offset(elapsed: duration, duration: duration, amplitude: amplitude, reduceMotion: false) == 0,
               "the shake ends at rest")
        assert(offset(elapsed: 99, duration: duration, amplitude: amplitude, reduceMotion: false) == 0,
               "past the end is at rest")
        assert(offset(elapsed: .nan, duration: duration, amplitude: amplitude, reduceMotion: false) == 0,
               "a bad elapsed time yields no movement")
        assert(offset(elapsed: 0.1, duration: 0, amplitude: amplitude, reduceMotion: false) == 0,
               "a zero duration yields no movement")
    }
}