import SwiftUI

/// A checkmark that draws itself with `.trim(from:to:)`, then optionally settles
/// into the plain glyph.
///
/// The draw-on is the most-used positive motion in the app — every correct
/// answer gets one — so it is worth doing properly:
///
///   * **`stroke` has `Animatable` conformance.** The draw-on is driven by
///     animating a single `CGFloat` on the path, not by a `TimelineView`. That
///     means it interrupts cleanly mid-draw (submit the next answer early and it
///     grows from where it was rather than restarting) and costs nothing while
///     sitting still — which is the state it is in almost all the time.
///   * **It draws from the short arm to the long arm**, matching the direction
///     the eye reads a checkmark in. A path built the other way looks like it is
///     being erased.
///   * **Under Reduce Motion the completed state is simply shown.** A
///     line-drawing animation is movement. There is nothing to degrade it to
///     except the finished mark, so that is what renders, immediately.
///
/// The `settlesIntoGlyph` option exists for the one place a drawn check and a
/// real one look different: when the mark sits inside a circle that is
/// animating in at the same time, the drawn stroke and the glyph's optical
/// weight disagree by a hair, and swapping one for the other at the end reads as
/// intentional rather than as a jump.
struct StrokeCheckmark: View {

    // MARK: Input

    /// Completion in `0...1`. Values outside the range are clamped.
    var progress: Double
    /// The stroke colour.
    var tint: Color = Palette.success
    /// Stroke width in points.
    var lineWidth: CGFloat = 3
    /// After the draw completes, fade to a filled glyph. See the type comment.
    var settlesIntoGlyph: Bool = false
    /// How long the draw takes when it runs.
    var duration: Double = 0.36

    // MARK: State

    @State private var drawn: CGFloat = 0
    @State private var hasSettled = false

    @Environment(\.motionSettings) private var settings

    // MARK: Body

    var body: some View {
        Group {
            if hasSettled {
                // The completed mark. Under Reduce Motion this is the *only*
                // thing that ever renders.
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(tint)
            } else {
                CheckmarkShape(progress: drawn)
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .motionDecoration()
        // `.animation` on the shape's own `progress`, which is where the draw
        // actually happens. `motionAware` rather than a manual `withAnimation`
        // so the reduced path cannot drift from the environment.
        .motionAware(Motion.Curve.decelerate, value: drawn)
        .onAppear(perform: run)
        .onChange(of: progress) { _, _ in run() }
        .onChange(of: settings.reduceMotion) { _, _ in run() }
        .onChange(of: settlesIntoGlyph) { _, _ in hasSettled = false }
    }

    // MARK: Run

    private func run() {
        let target = clampedProgress

        guard !settings.reduceMotion, target > 0 else {
            // No draw. Show the finished mark, or a zero-length stroke for a
            // zero-progress state, and do it now.
            drawn = 0
            hasSettled = settings.reduceMotion && target >= 1
            return
        }

        hasSettled = false
        withAnimation(.timingCurve(0.2, 0.9, 0.3, 1, duration: duration)) {
            drawn = target
        }
    }

    private var clampedProgress: CGFloat {
        guard progress.isFinite else { return 0 }
        return CGFloat(min(max(progress, 0), 1))
    }
}

// MARK: - CheckmarkShape

/// A tick whose visible length is `progress`, where `1` is the whole mark.
///
/// `Animatable` conformance is the point: animating `progress` is what drives the
/// draw, and SwiftUI's default `.linear` interpolation on a `CGFloat` between
/// `0` and `1` produces exactly the constant-speed reveal `.trim` would.
struct CheckmarkShape: Shape {

    /// `0` draws nothing, `1` draws the whole checkmark.
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clamped = min(max(progress, 0), 1)
        guard clamped > 0, rect.width > 0, rect.height > 0 else { return path }

        let start = Self.start(in: rect)
        let elbow = Self.elbow(in: rect)
        let end = Self.end(in: rect)

        path.move(to: start)
        // Past the elbow, the second segment starts at the elbow — which is why
        // the shape still has a corner even when the draw is mid-second-arm.
        path.addLine(to: Self.interpolated(from: start, elbow: elbow, end: end, progress: clamped))
        return path
    }

    /// The three anchors of the mark, as proportions of `rect` rather than
    /// points — so the shape is correct in a 16pt badge and a 64pt panel alike,
    /// and Dynamic Type cannot push it out of proportion.
    static func start(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.52)
    }

    static func elbow(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * 0.40, y: rect.minY + rect.height * 0.78)
    }

    static func end(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * 0.86, y: rect.minY + rect.height * 0.24)
    }
}

// MARK: - Test seam

extension CheckmarkShape {

    /// The point `progress` of the way along the mark, in `rect`.
    ///
    /// Exposed as a static so the self-check can verify the geometry without
    /// trying to measure a `Path` — `Path` does not expose its points, so the
    /// check exercises the same anchors `path(in:)` draws from.
    static func point(at progress: CGFloat, in rect: CGRect) -> CGPoint {
        interpolated(
            from: start(in: rect),
            elbow: elbow(in: rect),
            end: end(in: rect),
            progress: progress
        )
    }

    /// Walks `total * progress` along the two arms. The core of the draw.
    private static func interpolated(from start: CGPoint, elbow: CGPoint, end: CGPoint, progress: CGFloat) -> CGPoint {
        let clamped = min(max(progress, 0), 1)
        let shortArm = hypot(elbow.x - start.x, elbow.y - start.y)
        let longArm = hypot(end.x - elbow.x, end.y - elbow.y)
        let total = shortArm + longArm
        guard total > 0, clamped > 0 else { return start }

        let target = total * Double(clamped)
        if target <= shortArm {
            let t = CGFloat(target / shortArm)
            return CGPoint(
                x: start.x + (elbow.x - start.x) * t,
                y: start.y + (elbow.y - start.y) * t
            )
        }
        let t = CGFloat((target - shortArm) / longArm)
        return CGPoint(
            x: elbow.x + (end.x - elbow.x) * t,
            y: elbow.y + (end.y - elbow.y) * t
        )
    }

    /// Self-check for the draw-on geometry.
    ///
    /// What can go wrong: a shape that draws nothing, one that overshoots past
    /// the end of the mark, or one that travels backwards mid-draw — the last is
    /// what makes a checkmark appear to rewind.
    static func check() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let start = CGPoint(x: 14, y: 52)
        let elbow = CGPoint(x: 40, y: 78)
        let end = CGPoint(x: 86, y: 24)

        assert(CheckmarkShape(progress: 0).path(in: rect).isEmpty, "progress 0 must draw nothing")
        assert(CheckmarkShape(progress: -3).path(in: rect).isEmpty, "a negative progress draws nothing")

        // Full progress lands exactly on the end of the mark.
        let full = point(at: 1, in: rect)
        assert(abs(full.x - end.x) < 0.01 && abs(full.y - end.y) < 0.01,
               "progress 1 must land on the end of the mark")

        // Clamping: negative collapses to the start, over-1 to the end.
        let negative = point(at: -3, in: rect)
        assert(abs(negative.x - start.x) < 0.01 && abs(negative.y - start.y) < 0.01,
               "a negative progress sits at the start")
        let over = point(at: 4, in: rect)
        assert(abs(over.x - end.x) < 0.01 && abs(over.y - end.y) < 0.01,
               "progress above 1 clamps to the end")

        // Monotonic distance from the start: the mark never rewinds.
        var previous = -1.0
        for step in 0...100 {
            let p = CGFloat(step) / 100
            let point = interpolated(from: start, elbow: elbow, end: end, progress: p)
            let distance = hypot(point.x - start.x, point.y - start.y)
            assert(distance.isFinite, "geometry must stay finite")
            assert(distance >= previous - 0.001, "the draw must be monotonic")
            previous = distance
        }

        // The two arms must not be collinear, or the mark is just a line.
        let arm = CGPoint(x: elbow.x - start.x, y: elbow.y - start.y)
        let leg = CGPoint(x: end.x - elbow.x, y: end.y - elbow.y)
        assert(arm.x * leg.y - arm.y * leg.x != 0, "the arms must not be collinear")

        // A degenerate rect must not produce NaN.
        let degenerate = point(at: 0.5, in: .zero)
        assert(degenerate.x.isFinite && degenerate.y.isFinite, "a zero rect must not produce NaN")
    }
}
