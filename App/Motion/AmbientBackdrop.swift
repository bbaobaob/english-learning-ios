import SwiftUI

/// A slow, low-contrast animated backdrop for onboarding pages and the Home hero.
///
/// The brief for this one is restraint, and that is a harder constraint than it
/// looks. A backdrop that competes with the text on top of it is worse than no
/// backdrop, and a learning app's onboarding pages carry a paragraph of copy each.
/// So every parameter here is chosen to be *unnoticeable while present*:
///
///   * **Frame rate: 15fps, and only 12fps on iOS 18+ `MeshGradient`.** This is
///     the one deliberate performance compromise in the folder. A backdrop is a
///     very large, very low-frequency surface — a gradient blob moving slowly
///     does not gain anything visible from 120Hz, because the eye has nothing to
///     track, and it costs a full-screen repaint every frame it runs at. 15fps is
///     well above the threshold where slow motion reads as stepped (≈8fps) and
///     three times cheaper than a display-refresh loop. Every *other* effect in
///     `App/Motion` runs at the display rate, because they are small and their
///     motion is the point.
///   * **Low contrast by construction.** The blobs sit at a fraction of the
///     accent's opacity, blended into the page ground. The backdrop must be
///     visible in a screenshot and invisible in peripheral vision.
///   * **It never moves anything a finger is on.** No hit testing, no
///     accessibility, and it sits behind the content in the z-order.
///
/// Under **Reduce Motion** it is a static gradient. Under **Reduce
/// Transparency** it is a static *opaque* gradient with no layering at all,
/// because a soft multi-blob wash is made of overlapping translucent shapes and
/// there is no honest way to keep it without translucency.
///
/// On **iOS 18+** it upgrades to `MeshGradient`, which is genuinely better than
/// layered radial gradients for this job — it interpolates smoothly with no
/// banding, and it costs one draw instead of four. Gated, because the app
/// deploys to iOS 17.
struct AmbientBackdrop: View {

    // MARK: Input

    /// Which of the two backdrops to draw.
    var style: Style = .hero
    /// Slows or stops the drift without changing the palette. Used when the
    /// backdrop sits behind a busy screen.
    var intensity: Double = 1

    // MARK: Style

    /// Two looks. They differ in *composition*, not in colour — both are built
    /// from the same brand accent so neither can fight the app's palette.
    enum Style: Equatable {
        /// Onboarding: one slow wash from the top-left, very open, leaving the
        /// lower two-thirds almost entirely clear for the copy.
        case onboarding
        /// Home hero: two offset blobs low and high, still restrained.
        case hero

        /// The blob centres, as fractions of the view's size. Written down so the
        /// two styles cannot accidentally become the same composition.
        var blobOrigins: [CGPoint] {
            switch self {
            case .onboarding:
                return [CGPoint(x: 0.18, y: 0.08), CGPoint(x: 0.82, y: 0.30)]
            case .hero:
                return [CGPoint(x: 0.12, y: 0.18), CGPoint(x: 0.88, y: 0.62)]
            }
        }

        /// How far a blob drifts from its origin, as a fraction of the view.
        var drift: Double {
            switch self {
            case .onboarding: return 0.05
            case .hero: return 0.08
            }
        }
    }

    // MARK: State

    /// Whether the backdrop is animating at all.
    @State private var isAnimating = false

    @Environment(\.motionSettings) private var settings

    // MARK: Frame budget
    //
    // Documented here rather than in a comment elsewhere, because this is the
    // number someone will want to "fix" by raising it.

    /// Frames per second for the gradient wash. `15` on iOS 17–18.
    private static let washFPS: Double = 15
    /// Frames per second for the `MeshGradient` path, iOS 18+.
    private static let meshFPS: Double = 12
    /// Seconds for one full drift cycle. Long on purpose: a fast backdrop is
    /// animated wallpaper, and this is a page background.
    private static let driftPeriod: Double = 24

    // MARK: Body

    var body: some View {
        Group {
            if settings.reduceMotion || settings.reduceTransparency {
                // The static fallback. Under Reduce Transparency it is fully
                // opaque, because layered translucency is exactly what the
                // setting forbids.
                staticFallback
            } else if isAnimating {
                animated
            } else {
                staticFallback
            }
        }
        // A backdrop is decoration and must never intercept a touch meant for the
        // content on top of it.
        .allowsHitTesting(false)
        .motionDecoration()
        .onAppear(perform: start)
        .onChange(of: style) { _, _ in start() }
        .onChange(of: settings.reduceMotion) { _, _ in start() }
        .onChange(of: settings.reduceTransparency) { _, _ in start() }
        .onDisappear { isAnimating = false }
    }

    // MARK: Static

    /// A single, still gradient. Shown under Reduce Motion, under Reduce
    /// Transparency, and while the app is not drawing frames.
    private var staticFallback: some View {
        LinearGradient(
            colors: backdropColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .drawingGroup()  // One cached bitmap for a static gradient.
        .accessibilityHidden(true)
    }

    private var backdropColors: [Color] {
        settings.reduceTransparency
            // Opaque: the page ground itself, lifted toward the accent. No alpha.
            ? [Palette.brand.opacity(1).mix(with: Palette.background, by: 0.88),
               Palette.background]
            // Translucent wash over whatever is behind it, at a strength low
            // enough to read as texture rather than as colour.
            : [Palette.brand.opacity(0.10 * clampedIntensity),
               Palette.brandSoft.opacity(0.16 * clampedIntensity),
               Color.clear]
    }

    // MARK: Animated

    @ViewBuilder
    private var animated: some View {
        if #available(iOS 18, *) {
            meshBackdrop
        } else {
            canvasBackdrop
        }
    }

    /// iOS 18+: one `MeshGradient`, animated by moving three of its points.
    @available(iOS 18, *)
    private var meshBackdrop: some View {
        TimelineView(.animation(minimumInterval: 1 / Self.meshFPS, paused: false)) { context in
            let t = drift(at: context.date)
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    // Row 1 — the two drifting corners.
                    .init(0.0, 0.0),
                    SIMD2<Float>(Float(0.5 + 0.18 * t), Float(0.12 * t)),
                    .init(1.0, Float(0.08 * t)),
                    // Row 2 — a counter-drift on the right edge.
                    .init(Float(-0.06 * t), 0.5),
                    .init(0.5, 0.5),
                    .init(1.0, Float(0.5 + 0.14 * t)),
                    // Row 3 — anchored, so the bottom stays clear for copy.
                    .init(0.0, 1.0),
                    .init(0.5, Float(0.94 - 0.06 * t)),
                    .init(1.0, 1.0),
                ],
                colors: meshColors
            )
            .drawingGroup()
        }
    }

    @available(iOS 18, *)
    private var meshColors: [SIMD3<Float>] {
        // `MeshGradient` takes linear SIMD3 floats, not `Color`, so the accent
        // has to be resolved to components. Done once per body evaluation, not
        // per frame — the timeline closure only reads the array.
        [brandRGB, brandSoftRGB, clearRGB]
    }

    private var brandRGB: SIMD3<Float> { rgb(from: Palette.brand) }
    private var brandSoftRGB: SIMD3<Float> { rgb(from: Palette.brandSoft) }
    private var clearRGB: SIMD3<Float> { SIMD3<Float>(0, 0, 0) }

    /// `Color` → linear RGB for `MeshGradient`.
    ///
    /// Uses the resolved `UIColor`, so this follows Dark Mode and Increase
    /// Contrast exactly as the rest of the palette does. No hand-entered
    /// constants — that is what would have made the mesh drift out of sync with
    /// the accent in Dark Mode.
    private func rgb(from color: Color) -> SIMD3<Float> {
        guard let components = color.rgba(of: color) else { return SIMD3<Float>(0, 0, 0) }
        return SIMD3<Float>(
            Float(components.r * components.a),
            Float(components.g * components.a),
            Float(components.b * components.a)
        )
    }

    /// iOS 17: a `Canvas` with soft radial blobs. Two draws rather than nine
    /// mesh points, which is why the mesh path is preferred where available.
    private var canvasBackdrop: some View {
        TimelineView(.animation(minimumInterval: 1 / Self.washFPS, paused: false)) { context in
            Canvas { canvas, size in
                let t = drift(at: context.date)
                let edge = max(size.width, size.height)
                let driftLength = style.drift * Double(edge)

                for (index, origin) in style.blobOrigins.enumerated() {
                    // Counter-phase per blob, so they never move in lockstep and
                    // the result never looks like a single translating layer.
                    let phase = t + Double(index) * 0.5
                    let angle = phase * 2 * .pi
                    let cx = origin.x * Double(size.width) + cos(angle) * driftLength
                    let cy = origin.y * Double(size.height) + sin(angle) * driftLength
                    let radius = edge * (0.55 + 0.05 * sin(angle))

                    let rect = CGRect(
                        x: cx - radius,
                        y: cy - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    canvas.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(
                            Gradient(colors: [
                                blobColor(index).opacity(0.16 * clampedIntensity),
                                blobColor(index).opacity(0),
                            ]),
                            center: CGPoint(x: cx, y: cy),
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                }
            }
        }
    }

    private func blobColor(_ index: Int) -> Color {
        index == 0 ? Palette.brand : Palette.brandSoft
    }

    // MARK: Clock

    private var clampedIntensity: Double {
        guard intensity.isFinite else { return 1 }
        return min(max(intensity, 0), 1)
    }

    private func start() {
        // Both settings stop it. Reduce Motion for the movement, Reduce
        // Transparency for the translucency the wash is made of.
        isAnimating = !settings.reduceMotion && !settings.reduceTransparency && clampedIntensity > 0
    }

    /// Wrapped drift position, `-1...1`, so the motion is symmetric about the
    /// origin and never accumulates drift over a long session.
    private func drift(at date: Date) -> Float {
        let period = Self.driftPeriod
        guard period > 0 else { return 0 }
        let interval = date.timeIntervalSinceReferenceDate
        guard interval.isFinite else { return 0 }
        let phase = interval.truncatingRemainder(dividingBy: period) / period
        // A raised cosine: it eases to a stop at each end of the cycle, which is
        // what makes the backdrop feel like a slow breath rather than an
        // oscillation.
        return Float(cos(phase * 2 * .pi))
    }
}

// MARK: - Blend helper

extension Color {
    /// Mixes this colour toward `other` by `amount`, in `0...1`.
    ///
    /// Used by the Reduce Transparency backdrop, which needs an *opaque* colour
    /// derived from the accent rather than the accent at reduced alpha.
    func mix(with other: Color, by amount: Double) -> Color {
        let clamped = amount.isFinite ? min(max(amount, 0), 1) : 0
        guard let a = rgba(of: self), let b = rgba(of: other) else { return self }
        let t = CGFloat(clamped)
        return Color(
            .sRGB,
            red: a.r + (b.r - a.r) * t,
            green: a.g + (b.g - a.g) * t,
            blue: a.b + (b.b - a.b) * t,
            opacity: a.a + (b.a - a.a) * t
        )
    }

    /// Resolves a `Color` to straight RGBA.
    ///
    /// `getRed` fails on a non-RGB colour space (a pattern colour, or a greyscale
    /// one), so it is handled explicitly rather than assumed — a backdrop that
    /// silently falls back to black in Dark Mode would be a real bug, and this
    /// is the cheapest way to make it visible in a test instead.
    /// Internal rather than private so ``rgb(from:)`` in `AmbientBackdrop` — in
    /// this same file — can share it. Not exposed publicly on purpose.
    func rgba(of color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        let resolved = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if resolved.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return (r, g, b, a)
        }
        var white: CGFloat = 0
        if resolved.getWhite(&white, alpha: &a) {
            return (white, white, white, a)
        }
        return nil
    }
}