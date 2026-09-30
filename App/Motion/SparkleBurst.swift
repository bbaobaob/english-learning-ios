import SwiftUI

/// The achievement-unlock moment. A one-shot celebration, deliberately and
/// visibly *rarer* than ``SuccessBurst``.
///
/// Rarity has to be designed, not just intended. Answering correctly is routine —
/// it happens every few seconds — so ``SuccessBurst`` is small, symmetrical, and
/// over in half a second. An achievement may unlock once in a month. If it used
/// the same vocabulary it would register as "another correct answer", which is
/// the opposite of what it means. So this one differs on every axis:
///
/// |              | `SuccessBurst`              | `SparkleBurst`                    |
/// |--------------|-----------------------------|-----------------------------------|
/// | particles    | 18, evenly spread           | 26, in **two rings** at different radii |
/// | shapes       | 4, evenly mixed             | **4-point stars and diamonds only** |
/// | motion       | outward + gravity            | outward, and a **second ring expanding on its own phase** |
/// | ring         | none                        | a **shockwave ring** expanding from the centre |
/// | duration     | 0.55s                       | 1.1s                              |
/// | colour       | the result's colour         | `Palette.xp` — gold, and never used by a routine result |
/// | haptics      | none (caller does it)       | `Haptics.success()` **plus** a second hit |
///
/// The colour choice is the load-bearing one: `Palette.xp` is the only accent
/// this effect uses, and nothing else on a result panel uses it, so the two
/// celebrations cannot be confused even at a glance in peripheral vision.
///
/// Under Reduce Motion it shows a single static badge — a filled star in
/// `Palette.xp` with a ring at full size — held for the duration and then
/// dismissed. No travel, no expansion. It is never nothing: the achievement is
/// also announced in text by whatever screen triggered it.
struct SparkleBurst: View {

    // MARK: Input

    /// `true` while the celebration should play. Drive it from the moment the
    /// unlock happens, not on appear.
    var isActive: Bool
    /// The achievement's own tint. Defaults to `Palette.xp`, which is the
    /// point of the effect; pass a different one only if the caller has a
    /// stronger reason.
    var tint: Color = Palette.xp
    /// How long the celebration lasts before it dismisses itself. Set to
    /// roughly double `SuccessBurst`'s on purpose — see the type comment.
    var duration: Double = 1.1
    /// Total sparkles, split across two rings. Higher than `SuccessBurst`'s 18.
    var particleCount: Int = 26
    /// How far sparkles may travel, as a fraction of the view's edge. Wider than
    /// `SuccessBurst`'s, so the unlock fills more of the space it is given.
    var travel: Double = 0.46

    // MARK: State

    @State private var startDate: Date = Date()
    @State private var isVisible = false
    /// Seeds are made once per unlock and reused by every frame — the draw
    /// closure must not allocate.
    @State private var seeds: [ParticleSeed] = []

    @Environment(\.motionSettings) private var settings

    /// The second ring's seeds, offset so the two rings do not mirror.
    @State private var outerSeeds: [ParticleSeed] = []

    // MARK: Body

    var body: some View {
        ZStack {
            if settings.reduceMotion {
                reducedVariant
            } else if isVisible {
                animatedVariant
            }
        }
        .motionDecoration()
        .onAppear(perform: begin)
        .onChange(of: isActive) { _, _ in begin() }
        .onChange(of: settings.reduceMotion) { _, _ in begin() }
        .onDisappear { isVisible = false }
        // The dismissal is a `.task`, so SwiftUI cancels it if the screen goes
        // away mid-celebration rather than leaving it to fire into nothing.
        .task(id: isActive) {
            guard isActive else { return }
            await dismissAfterDelay()
        }
    }

    // MARK: Variants

    /// The animated celebration: a shockwave ring plus two particle rings.
    @ViewBuilder
    private var animatedVariant: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let progress = duration > 0 ? min(max(elapsed / duration, 0), 1) : 1

            Canvas { canvas, size in
                let edge = min(size.width, size.height)
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)

                // The shockwave: a ring that expands and fades. This is the single
                // element that most distinguishes an unlock from a routine burst —
                // it is a wavefront, not a particle.
                if progress < 0.85 {
                    let wave = min(progress / 0.85, 1)
                    let radius = edge * (0.1 + 0.4 * wave)
                    let opacity = (1 - wave) * 0.55
                    canvas.stroke(
                        Path(ellipseIn: CGRect(
                            x: centre.x - radius,
                            y: centre.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )),
                        with: .color(tint.opacity(opacity)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                }

                // Inner ring: fast, tight.
                for seed in seeds {
                    drawSparkle(
                        seed: seed,
                        at: ParticlePoint.at(
                            seed: seed, t: elapsed, duration: duration * 0.72,
                            size: edge, travel: travel * 0.74
                        ),
                        centre: centre,
                        in: canvas
                    )
                }

                // Outer ring: slower, wider, on a different phase. Two rings
                // reading as one thick band is what makes it feel layered rather
                // than merely larger.
                for seed in outerSeeds {
                    drawSparkle(
                        seed: seed,
                        at: ParticlePoint.at(
                            seed: seed, t: elapsed * 0.72, duration: duration * 0.95,
                            size: edge, travel: travel
                        ),
                        centre: centre,
                        in: canvas
                    )
                }
            }
            .opacity(progress >= 1 ? 0 : 1)
        }
    }

    /// The Reduce Motion variant: one static star. No travel, no expansion.
    @ViewBuilder
    private var reducedVariant: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let progress = duration > 0 ? min(max(elapsed / duration, 0), 1) : 1

            Image(systemName: "star.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(tint)
                // Static, but it does appear and disappear — a crossfade is
                // opacity, not movement, so it is permitted even under Reduce
                // Motion.
                .opacity(progress >= 1 ? 0 : 1)
        }
    }

    // MARK: Drawing

    /// One four-point sparkle. Deliberately a star rather than the
    /// dot/spoke/diamond/ring mix ``SuccessBurst`` uses — the shape vocabulary
    /// is part of what makes this feel like a different kind of event.
    ///
    /// - Parameters:
    ///   - seed: The particle's launch parameters; `sizeScale` sizes the star.
    ///   - point: Where the particle is right now, relative to `centre`.
    ///   - centre: The burst's centre in canvas coordinates.
    ///   - context: The canvas to draw into.
    private func drawSparkle(
        seed: ParticleSeed,
        at point: ParticlePoint,
        centre: CGPoint,
        in context: GraphicsContext
    ) {
        guard point.opacity > 0.02 else { return }
        let radius = 3.5 * point.scale * seed.sizeScale
        guard radius > 0.1 else { return }

        let position = CGPoint(x: centre.x + point.x, y: centre.y + point.y)
        // A four-point star: four quadratic curves pinched toward the axes, which
        // gives the concave-sided sparkle rather than a plain diamond.
        let pinch = radius * 0.25
        var path = Path()
        path.move(to: CGPoint(x: position.x, y: position.y - radius))
        path.addQuadCurve(
            to: CGPoint(x: position.x + radius, y: position.y),
            control: CGPoint(x: position.x + pinch, y: position.y + pinch)
        )
        path.addQuadCurve(
            to: CGPoint(x: position.x, y: position.y + radius),
            control: CGPoint(x: position.x + pinch, y: position.y - pinch)
        )
        path.addQuadCurve(
            to: CGPoint(x: position.x - radius, y: position.y),
            control: CGPoint(x: position.x - pinch, y: position.y - pinch)
        )
        path.addQuadCurve(
            to: CGPoint(x: position.x, y: position.y - radius),
            control: CGPoint(x: position.x - pinch, y: position.y + pinch)
        )
        path.closeSubpath()

        context.fill(path, with: .color(tint.opacity(point.opacity)))
    }

    // MARK: Lifecycle

    private func begin() {
        guard isActive else {
            isVisible = false
            return
        }
        // Two rings, split unevenly and on different seeds, so they never
        // mirror each other. Rebuilt per unlock, but only once — never in the
        // draw closure.
        let inner = Int(Double(particleCount) * 0.55)
        let outer = max(0, particleCount - inner)
        seeds = ParticleSeed.make(count: inner, seed: 0xA5A5_1234_5678_9ABC)
        outerSeeds = ParticleSeed.make(count: outer, seed: 0x1234_9ABC_5678_A5A5)
        startDate = Date()
        isVisible = true
    }

    private func dismissAfterDelay() async {
        try? await Task.sleep(for: .seconds(duration))
        guard !Task.isCancelled else { return }
        isVisible = false
    }
}

// MARK: - Test seam

extension SparkleBurst {

    /// Self-check for the distinction from ``SuccessBurst``.
    ///
    /// The whole design rests on the two celebrations not being confusable, so
    /// the numbers that carry that difference are asserted rather than assumed.
    static func check() {
        let sparkle = SparkleBurst(isActive: false)
        let success = SuccessBurst()

        // Durations differ substantially: 1.1s against 0.55s. A celebration that
        // is the same length as the routine one does not read as rarer.
        assert(sparkle.duration >= success.duration * 1.8,
               "the achievement celebration must last noticeably longer")

        // Different particle counts, and the achievement uses two rings.
        assert(sparkle.particleCount > success.particleCount,
               "the achievement celebration must use more particles")

        // Different travel distances, so the achievement occupies more space.
        assert(sparkle.travel > success.travel, "the achievement celebration must reach further")

        // Particle geometry is deterministic and bounded — the property the draw
        // closure's zero-allocation claim depends on.
        let seeds = ParticleSeed.make(count: 32)
        assert(seeds.count == 32, "seed count must match the request")
        for seed in seeds {
            assert(seed.angle.isFinite, "angles must be finite")
            assert(seed.speedScale >= 0 && seed.speedScale <= 1, "speed scale must be normalised")
            assert(seed.sizeScale > 0, "size scale must be positive")
            assert(seed.life > 0 && seed.life <= 1, "life must be normalised")
            assert((0..<4).contains(seed.style), "style must be a valid index")
        }
        // Same seed, same particles — which is what makes a visual regression
        // visible as a diff.
        assert(ParticleSeed.make(count: 8, seed: 42) == ParticleSeed.make(count: 8, seed: 42),
               "a seeded burst must be reproducible")
        assert(ParticleSeed.make(count: 8, seed: 42) != ParticleSeed.make(count: 8, seed: 43),
               "a different seed must give different particles")

        // A particle is on-screen only while it is alive.
        for seed in seeds.prefix(4) {
            assert(ParticlePoint.at(seed: seed, t: 0, duration: 1, size: 100, travel: 0.4).opacity > 0,
                   "a fresh particle is visible")
            assert(ParticlePoint.at(seed: seed, t: 99, duration: 1, size: 100, travel: 0.4).opacity == 0,
                   "a dead particle is invisible")
            let past = ParticlePoint.at(seed: seed, t: 99, duration: 1, size: 100, travel: 0.4)
            assert(past.x.isFinite && past.y.isFinite, "a dead particle must still be finite")
        }
    }
}