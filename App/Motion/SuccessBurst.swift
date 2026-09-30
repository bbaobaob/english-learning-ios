import SwiftUI

/// The routine celebration for a correct answer: a short, symmetric particle
/// burst drawn in a `Canvas`.
///
/// Deliberately *small*. This fires after every right answer, which in a lesson
/// is every few seconds, so anything larger stops being a reward and starts
/// being an interruption. It is designed to be over before the learner has
/// finished reading the explanation underneath it.
///
/// Colour comes from `tint`, which callers pass as `Palette.success` for a
/// correct answer and `Palette.brand` for a neutral positive — the burst derives
/// its highlight and shadow from that one colour instead of hard-coding a
/// celebratory green, so it stays correct in Dark Mode, under Increase
/// Contrast, and if the app's accent ever changes.
///
/// Under Reduce Motion it shows a single brief, non-moving crossfade of the
/// ring at the centre: enough to mark the moment, nothing that travels. It is
/// never nothing — the result panel's own text carries the meaning, and this
/// only needs to acknowledge it.
///
/// Pair with ``Haptics/success()``.
struct SuccessBurst: View {

    // MARK: Input

    /// The burst's base colour.
    var tint: Color = Palette.success
    /// Particles per burst. Kept low: this fires often, and 18 reads as a burst
    /// where 40 reads as an explosion.
    var particleCount: Int = 18
    /// Total lifetime in seconds. Short on purpose — see the type comment.
    var duration: Double = 0.55
    /// How far particles may travel, as a fraction of the view's edge.
    var travel: Double = 0.42

    // MARK: State

    /// `true` while the burst is running. The caller drives this from their own
    /// result state; the burst does not guess when an answer was submitted.
    /// Defaults to `false` so the burst is inert until something starts it.
    var isActive: Bool = false

    @State private var startDate: Date = Date()
    @State private var isVisible = false

    @Environment(\.motionSettings) private var settings

    /// Made once per burst and reused by every frame. Holding it in `@State`
    /// rather than computing it in the draw closure is what keeps the closure
    /// allocation-free.
    @State private var seeds: [ParticleSeed] = []

    // MARK: Body

    var body: some View {
        ZStack {
            // Reduce Motion: the ring fades in and out in place. No particle
            // ever leaves the centre, so nothing travels across the screen.
            if settings.reduceMotion {
                reducedVariant
            } else if isVisible {
                canvas
            }
        }
        .motionDecoration()
        .onAppear(perform: begin)
        .onChange(of: isActive) { _, _ in begin() }
        .onChange(of: settings.reduceMotion) { _, _ in begin() }
        .onDisappear { isVisible = false }
        // One task per burst, cancelled by SwiftUI on disappear.
        .task(id: isActive) {
            guard isActive else { return }
            await dismissAfterDelay()
        }
    }

    @ViewBuilder
    private var canvas: some View {
        // Past the end the burst simply draws nothing; the view-level `.task`
        // below is what unmounts this timeline, so a hidden timeline never
        // keeps ticking.
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            if elapsed >= duration {
                Color.clear
            } else {
                particleLayer(elapsed: elapsed)
            }
        }
    }

    /// The Reduce Motion variant: one ring, fading, at the centre. It expands in
    /// place — a scale on a ring centred on itself moves no edge far enough to
    /// read as travel, but it is a fade, which is the part Reduce Motion permits.
    private var reducedVariant: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let progress = duration > 0 ? min(max(elapsed / duration, 0), 1) : 1
            Circle()
                .stroke(tint, lineWidth: 2)
                .scaleEffect(0.92 + 0.08 * progress)
                .opacity((1 - progress) * 2)
        }
    }

    /// Ends the burst after `duration`.
    ///
    /// Attached with `.task(id: isActive)` on the view, never inside the
    /// `TimelineView` closure: a task inside a per-frame closure is torn down and
    /// respawned every frame, which is a spawn-a-task-per-frame bug.
    private func dismissAfterDelay() async {
        try? await Task.sleep(for: .seconds(duration))
        guard !Task.isCancelled else { return }
        finish()
    }

    // MARK: Drawing

    private func particleLayer(elapsed: Double) -> some View {
        Canvas { context, size in
            let edge = min(size.width, size.height)
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)

            // `for` over pre-built seeds. No map, no filter, no array building:
            // every operation below is a scalar calculation.
            for seed in seeds {
                let point = ParticlePoint.at(
                    seed: seed,
                    t: elapsed,
                    duration: duration,
                    size: edge,
                    travel: travel
                )
                guard point.opacity > 0.02 else { continue }

                let radius = edge * 0.045 * point.scale * seed.sizeScale
                let position = CGPoint(x: centre.x + point.x, y: centre.y + point.y)

                context.drawParticle(
                    style: seed.style,
                    at: position,
                    radius: radius,
                    color: particleColor(opacity: point.opacity)
                )
            }
        }
    }

    /// One particle's colour. A single flat colour with a shared alpha; the
    /// variation between particles comes from their own opacity and size, which
    /// is cheaper than a per-particle gradient and reads the same at this size.
    private func particleColor(opacity: Double) -> Color {
        // Reduce Transparency collapses the effect toward a solid, higher-
        // contrast mark rather than a faint one — a faint mark is exactly what
        // the setting exists to avoid.
        settings.reduceTransparency
            ? tint.opacity(opacity)
            : tint.opacity(opacity * 0.85)
    }

    // MARK: Lifecycle

    private func begin() {
        guard isActive else {
            isVisible = false
            return
        }
        // Seeds are rebuilt per burst so two consecutive correct answers do not
        // throw identical particles, but only once, not per frame.
        seeds = ParticleSeed.make(count: particleCount)
        startDate = Date()
        isVisible = true
    }

    private func finish() {
        isVisible = false
        // No haptic here: the caller owns feedback. A celebration effect that
        // buzzes on its own would double up with `Haptics.success()` and give
        // the wrong intensity for the result.
    }
}

// MARK: - Drawing helpers

extension GraphicsContext {
    /// Draws one particle. Four shapes, chosen by index, so the burst has
    /// texture without the cost of a custom path per particle.
    ///
    /// Drawn with primitives rather than `Path` where possible: a circle or a
    /// line is faster than a built path, and at 6pt across nobody can tell.
    func drawParticle(style: Int, at position: CGPoint, radius: CGFloat, color: Color) {
        guard radius > 0.1 else { return }
        switch style {
        case 0:
            // A dot.
            fill(
                Path(ellipseIn: CGRect(
                    x: position.x - radius,
                    y: position.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .color(color)
            )
        case 1:
            // A short spoke. Reads as a spark rather than a dot.
            var path = Path()
            path.move(to: CGPoint(x: position.x - radius, y: position.y))
            path.addLine(to: CGPoint(x: position.x + radius, y: position.y))
            stroke(path, with: .color(color), lineWidth: max(1, radius * 0.5))
        case 2:
            // A small square, rotated 45° — a diamond.
            var path = Path()
            path.move(to: CGPoint(x: position.x, y: position.y - radius))
            path.addLine(to: CGPoint(x: position.x + radius, y: position.y))
            path.addLine(to: CGPoint(x: position.x, y: position.y + radius))
            path.addLine(to: CGPoint(x: position.x - radius, y: position.y))
            path.closeSubpath()
            fill(path, with: .color(color))
        default:
            // A tiny ring.
            let rect = CGRect(
                x: position.x - radius,
                y: position.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: max(1, radius * 0.35))
        }
    }
}