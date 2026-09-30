import SwiftUI

/// An animated progress ring, drop-in compatible with ``ProgressRing``.
///
/// Why this exists alongside `ProgressRing`: `ProgressRing` in
/// `App/Components/Stats.swift` animates its trim with
/// `.animation(Motion.standard, value:)`, which is correct for a ring that fills
/// once. A mastery or goal ring that goes from 12% to 48% while the learner is
/// reading needs to read as *movement* — the number changing and the arc
/// travelling at the same time, from where it was, in one gesture.
///
/// The difference is the leading edge. ``SweepHead`` paints a small rounded cap
/// at the tip of the arc, and the whole arc is drawn into a `Canvas` that is
/// sized to the ring rather than composed from layered `Circle`s. That is what
/// lets the sweep be interrupted mid-flight without the two layers fighting.
///
/// Under Reduce Motion it renders the completed arc immediately. A ring is
/// information — it is a percentage, and the label says so — so it still
/// updates; only the travel is removed.
///
/// Replace `ProgressRing(progress:)` with `RingSweep(progress:)` for goal and
/// mastery rings. It takes the same parameters and gains two optional ones.
struct RingSweep: View {

    // MARK: Input

    /// Completion in `0...1`. Values outside the range are clamped.
    let progress: Double
    /// Stroke width in points.
    var lineWidth: CGFloat = 8
    /// The arc's colour.
    var tint: Color = Palette.brand
    /// Text shown in the middle.
    var label: String?

    // MARK: State

    /// The animated value the arc is drawn from.
    @State private var sweep: Double = 0

    @Environment(\.motionSettings) private var settings

    // MARK: Body

    var body: some View {
        ZStack {
            ring
            if let label {
                Text(label)
                    .font(AppFont.mono(.headline, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    // Relative sizing, so the label scales with the ring and
                    // with Dynamic Type instead of being clipped at AX sizes.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(Spacing.xs)
            }
        }
        // `.accessibilityElement(children: .ignore)` + a spoken value, so
        // VoiceOver reads the percentage rather than announcing an unlabelled
        // graphic. Matches `ProgressRing`'s contract exactly.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Progress"))
        .accessibilityValue(Text(verbatim: Format.percent(clamped)))
        .onAppear(perform: settle)
        .onChange(of: clamped) { _, _ in settle() }
        .onChange(of: settings.reduceMotion) { _, _ in settle() }
    }

    // MARK: Ring

    @ViewBuilder
    private var ring: some View {
        if settings.reduceTransparency {
            // Opaque ring. Without translucency a soft track reads as a smudge,
            // so this uses the flat `Palette.field` track that `ProgressRing`
            // already uses.
            canvas(showsHead: false)
        } else {
            canvas(showsHead: true)
        }
    }

    private func canvas(showsHead: Bool) -> some View {
        Canvas { context, size in
            let line = size.width
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = (line - lineWidth) / 2

            // Track.
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: centre.x - radius,
                    y: centre.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .color(Palette.field),
                style: StrokeStyle(lineWidth: lineWidth)
            )

            guard sweep > 0 else { return }

            // Arc. `-90°` puts the start at twelve o'clock, matching
            // `ProgressRing`, so the two are visually interchangeable.
            var arc = Path()
            arc.addArc(center: centre,
                       radius: radius,
                       startAngle: .degrees(-90),
                       endAngle: .degrees(-90 + 360 * sweep),
                       clockwise: false)
            context.stroke(
                arc,
                with: .color(tint),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )

            // The leading edge: a small filled dot at the tip. This is the whole
            // reason the ring is drawn in a Canvas — it is what makes 12% → 48%
            // read as a travelling sweep rather than a redrawn arc.
            guard showsHead else { return }
            let angle = Angle.degrees(-90 + 360 * sweep)
            let head = CGPoint(
                x: centre.x + radius * cos(angle.radians),
                y: centre.y + radius * sin(angle.radians)
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: head.x - lineWidth * 0.5,
                    y: head.y - lineWidth * 0.5,
                    width: lineWidth,
                    height: lineWidth
                )),
                with: .color(tint)
            )
        }
        // The animation is on the drawn value, which is a state animation: it
        // runs on the CPU-free SwiftUI path, not a per-frame timeline. Nothing
        // here ticks while the value is still.
        .motionAware(Motion.Curve.spring, value: sweep)
    }

    // MARK: Value

    private var clamped: Double {
        progress.isFinite ? min(max(progress, 0), 1) : 0
    }

    private func settle() {
        guard !settings.reduceMotion else {
            // Snap. The percentage still updates — that is information, not
            // motion.
            withAnimation(nil) { sweep = clamped }
            return
        }
        withAnimation(Motion.Curve.spring) { sweep = clamped }
    }
}

// MARK: - Test seam

/// The pure geometry behind ``RingSweep``'s leading edge, kept separate so it
/// can be checked without a `Canvas`.
enum RingSweepGeometry: Equatable {
    /// The angle of the arc's tip, in degrees, for a sweep of `sweep`.
    ///
    /// Starts at -90 so a zero sweep sits at twelve o'clock rather than at three,
    /// matching the `rotationEffect(.degrees(-90))` the shape-based
    /// `ProgressRing` applies.
    static func headAngle(forSweep sweep: Double) -> Double {
        let clamped = sweep.isFinite ? min(max(sweep, 0), 1) : 0
        return -90 + 360 * clamped
    }

    /// The head's position, relative to the centre.
    static func headOffset(forSweep sweep: Double, radius: CGFloat) -> CGPoint {
        let radians = headAngle(forSweep: sweep) * .pi / 180
        return CGPoint(x: radius * cos(radians), y: radius * sin(radians))
    }
}

extension RingSweep {

    /// Self-check for the sweep geometry.
    static func check() {
        // A zero sweep sits at the top.
        let top = RingSweepGeometry.headOffset(forSweep: 0, radius: 10)
        assert(abs(top.x) < 0.001 && abs(top.y - (-10)) < 0.001,
               "a zero sweep starts at twelve o'clock")

        // A full sweep ends at the top again, having gone all the way round.
        let full = RingSweepGeometry.headOffset(forSweep: 1, radius: 10)
        assert(abs(full.x) < 0.001 && abs(full.y - (-10)) < 0.001,
               "a full sweep closes the circle")

        // A quarter sweep is at three o'clock: the arc is clockwise from the top.
        let quarter = RingSweepGeometry.headOffset(forSweep: 0.25, radius: 10)
        assert(abs(quarter.x - 10) < 0.001 && abs(quarter.y) < 0.001,
               "a quarter sweep reaches three o'clock")

        // Clamping, including the non-finite case.
        assert(RingSweepGeometry.headAngle(forSweep: 4) == 270, "progress above 1 clamps")
        assert(RingSweepGeometry.headAngle(forSweep: -2) == -90, "negative progress clamps to zero")
        assert(RingSweepGeometry.headAngle(forSweep: .nan) == -90, "a non-finite progress clamps to zero")

        // The head never leaves the ring.
        for step in 0...100 {
            let offset = RingSweepGeometry.headOffset(forSweep: Double(step) / 100, radius: 12)
            assert(offset.x.isFinite && offset.y.isFinite, "the head must stay finite")
            assert(abs(hypot(offset.x, offset.y) - 12) < 0.001, "the head stays on the ring")
        }
    }
}