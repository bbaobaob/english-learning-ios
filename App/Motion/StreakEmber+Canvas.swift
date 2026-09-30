import SwiftUI

// MARK: - Drawing
//
// Split from `StreakEmber.swift` so the geometry reads on its own. Everything
// here is closed-form in the elapsed phase: no particle state, no integration,
// nothing that can drift or accumulate if a frame is dropped.

extension StreakEmber {

    /// The flame. `date` is `nil` for the frozen static render.
    func flame(at date: Date?) -> some View {
        Canvas { context, size in
            let live = date.map(time(for:)) ?? 0
            let current = profile
            let centre = CGPoint(x: size.width / 2, y: size.height * 0.58)
            let edge = min(size.width, size.height)

            // A slow breath plus a faster tremor, both scaled by `flicker`. The
            // tremor is what stops this looking like an opacity pulse, which is
            // what most "flame" effects actually are.
            let breath = sin(live * 2 * .pi)
            let tremor = sin(live * 2 * .pi * 3.7) * 0.5 + sin(live * 2 * .pi * 6.1) * 0.25
            let wobble = (breath * 0.6 + tremor * 0.4) * current.flicker

            let height = edge * (0.82 + 0.06 * wobble)
            let width = edge * (0.46 + 0.05 * wobble)

            // Outer flame. The ramp is built from semantic accents rather than a
            // hard-coded orange, so it follows Dark Mode and the app's accent.
            context.fill(
                flamePath(centre: centre, width: width, height: height),
                with: .linearGradient(
                    Gradient(colors: flameColors),
                    startPoint: CGPoint(x: centre.x, y: centre.y - height),
                    endPoint: CGPoint(x: centre.x, y: centre.y + height * 0.5)
                )
            )

            // Inner core, only when the flame is hot enough for one to be
            // believable. A core on a day-1 flame would be a lie.
            guard current.intensity > 0.35 else { return }
            context.fill(
                flamePath(
                    centre: CGPoint(x: centre.x, y: centre.y + height * 0.12),
                    width: width * 0.55,
                    height: height * 0.5
                ),
                with: .color(coreColor)
            )

            // Ember trail. Skipped under Reduce Transparency: a soft glow needs
            // translucency, and without it these are just faint dots.
            guard !settings.reduceTransparency, date != nil, current.emberCount > 0 else { return }
            drawEmbers(context: context, edge: edge, live: live, current: current)
        }
        .accessibilityHidden(true)
    }

    /// The flame's colour ramp, from the semantic accents.
    private var flameColors: [Color] {
        [
            Palette.streak.opacity(settings.reduceTransparency ? 1 : 0.95),
            Palette.warning.opacity(settings.reduceTransparency ? 1 : 0.9),
        ]
    }

    private var coreColor: Color {
        Palette.surface.opacity(settings.reduceTransparency ? 1 : 0.75)
    }

    /// A teardrop flame: wide at the base, tapering to a point at the top.
    ///
    /// Two symmetric cubic curves, so the silhouette is identical at every size
    /// and Dynamic Type cannot distort it.
    private func flamePath(centre: CGPoint, width: CGFloat, height: CGFloat) -> Path {
        let half = width / 2
        let foot = centre.y + height * 0.42
        var path = Path()
        path.move(to: CGPoint(x: centre.x - half, y: foot))
        // Left flank up to the tip.
        path.addCurve(
            to: CGPoint(x: centre.x, y: centre.y - height * 0.58),
            control1: CGPoint(x: centre.x - half, y: centre.y - height * 0.1),
            control2: CGPoint(x: centre.x - half * 0.55, y: centre.y - height * 0.45)
        )
        // Right flank back down to the base.
        path.addCurve(
            to: CGPoint(x: centre.x + half, y: foot),
            control1: CGPoint(x: centre.x + half * 0.55, y: centre.y - height * 0.45),
            control2: CGPoint(x: centre.x + half, y: centre.y - height * 0.1)
        )
        path.closeSubpath()
        return path
    }

    /// Embers rising off the flame.
    ///
    /// Positions are closed-form in `live`, and each ember's phase comes from its
    /// index rather than from a random number, so the closure allocates nothing
    /// and two renders of the same phase are identical.
    private func drawEmbers(
        context: GraphicsContext,
        edge: CGFloat,
        live: Double,
        current: EmberProfile
    ) {
        for index in 0..<current.emberCount {
            let seed = Double(index) * 0.618
            let rise = (live * (0.4 + seed * 0.3) + seed).truncatingRemainder(dividingBy: 1)

            let x = edge * 0.5 + sin(seed * 2 * .pi + rise * 2) * edge * 0.16
            let y = edge * 0.3 - rise * edge * 0.34

            // Fade in and out across the ember's life.
            let opacity = sin(rise * .pi) * 0.8 * current.intensity
            guard opacity > 0.02 else { continue }

            let radius = edge * 0.035 * (1 - rise * 0.4)
            context.fill(
                Path(ellipseIn: CGRect(
                    x: x - radius,
                    y: y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .color(Palette.warning.opacity(opacity))
            )
        }
    }
}

// MARK: - Test seam

extension StreakEmber {

    /// Self-check for the streak → flame mapping.
    ///
    /// What matters and is easy to break: intensity never leaves `0...1`, day 1
    /// is dim, day 3 is brighter *and calmer* than day 1, intensity never
    /// regresses, the ramp is capped at 30 days, and negative input cannot
    /// produce nonsense.
    static func check() {
        // Total and bounded across the plausible range, including the negative
        // values a caller bug could pass.
        for days in -10...400 {
            let p = EmberProfile.forDays(days)
            assert(p.intensity.isFinite && p.intensity >= 0 && p.intensity <= 1,
                   "intensity must stay in 0...1 at \(days) days")
            assert(p.flicker.isFinite && p.flicker >= 0 && p.flicker <= 1,
                   "flicker must stay in 0...1 at \(days) days")
            assert(p.emberCount >= 0 && p.emberCount <= 12,
                   "ember count must stay bounded at \(days) days")
        }

        assert(EmberProfile.forDays(1).intensity < 0.25, "day 1 must be dim")
        assert(EmberProfile.forDays(0).intensity <= EmberProfile.forDays(1).intensity,
               "day 0 must not outshine day 1")

        let day1 = EmberProfile.forDays(1)
        let day3 = EmberProfile.forDays(3)
        assert(day3.intensity > day1.intensity, "day 3 must be brighter than day 1")
        assert(day3.flicker < day1.flicker, "day 3 must be calmer than day 1")

        // Intensity never regresses as the streak grows.
        var previous = -1.0
        for days in 0...60 {
            let intensity = EmberProfile.forDays(days).intensity
            assert(intensity >= previous - 0.0001, "intensity must not regress at \(days) days")
            previous = intensity
        }

        // The ramp is capped: a 200-day streak is not 7x a 4-day one.
        assert(abs(EmberProfile.forDays(200).intensity - EmberProfile.forDays(30).intensity) < 0.001,
               "the intensity ramp must be capped at 30 days")

        assert(EmberProfile.inactive.emberCount == 0, "an inactive streak has no embers")
    }
}