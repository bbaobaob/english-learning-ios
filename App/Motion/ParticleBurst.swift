import SwiftUI

// MARK: - ParticleBurst
//
// The physics behind both celebration effects, written down once.
//
// `SuccessBurst` and `SparkleBurst` need the same thing — N particles, given a
// direction and a speed, thrown outward and faded — and they need it to *differ*
// in shape and timing. So the simulation lives here and each effect supplies a
// shape and a duration.
//
// Three performance rules are enforced in this file rather than trusted to the
// call sites, because they are the difference between an effect that can live
// on a content screen and one that cannot:
//
//   1. **Seeds are computed once, not per frame.** A `Canvas` draw closure runs
//      up to 120 times a second; generating randomness inside it allocates on
//      every frame. `ParticleSeed` values are made when the burst starts and
//      reused, so the draw closure reads plain numbers.
//   2. **Positions are pure arithmetic.** No integration, no state, no
//      accumulation — `position(at:)` is a closed-form function of the elapsed
//      time, so the effect cannot drift if a frame is dropped.
//   3. **One `TimelineView`, and only while the burst is alive.** The caller
//      gates it on `isBursting`; the effect unmounts the timeline on completion
//      rather than leaving a paused one ticking behind a static frame.

/// One particle's immutable launch parameters. Made once per burst.
struct ParticleSeed: Equatable {
    /// 0...1 around the circle. Two particles with the same angle but different
    /// seeds still land differently, because speed and length differ too.
    let angle: Double
    /// 0...1 multiplier on the burst's base speed.
    let speedScale: Double
    /// 0...1 multiplier on the particle's size.
    let sizeScale: Double
    /// Particle lifetime in seconds, `0...duration`.
    let life: Double
    /// Which of the few shared motion styles this particle uses, so a burst can
    /// mix a few shapes without allocating a closure per particle.
    let style: Int
}

extension ParticleSeed {

    /// Deterministic pseudo-random seeds. A fixed LCG rather than `SystemRandom`,
    /// for two reasons: no allocation and no hidden entropy dependency, and the
    /// same burst replays identically, which makes a visual regression visible
    /// as a diff rather than as a shrug.
    ///
    /// ponytail: a hand-rolled xorshift is enough here. Swap for `SystemRandom`
    /// only if particles are ever seeded from a genuinely unpredictable source.
    static func make(count: Int, seed: UInt64 = 0x9E3779B97F4A7C15) -> [ParticleSeed] {
        var state = seed
        func next() -> Double {
            // xorshift64*
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return Double((state &* 0x2545F4914F6CDD1D) >> 11) / Double(1 << 53)
        }
        return (0..<max(0, count)).map { _ in
            ParticleSeed(
                // A full circle, biased slightly outward so the burst is not a
                // perfectly even ring, which reads as mechanical.
                angle: next() * 2 * .pi,
                speedScale: 0.55 + next() * 0.45,
                sizeScale: 0.6 + next() * 0.7,
                life: 0.55 + next() * 0.45,
                style: Int(next() * 4) % 4
            )
        }
    }
}

/// A particle's position at a point in its life. Pure: no state, no drift.
struct ParticlePoint: Equatable {
    let x: Double
    let y: Double
    /// 0...1 opacity. Fades out on a curve so particles linger then vanish
    /// rather than fading linearly and looking like a mistake.
    let opacity: Double
    /// 0...1 scale, for the shrink at the end of life.
    let scale: Double
}

extension ParticlePoint {

    /// Where a seeded particle is `t` seconds into a burst, relative to a size
    /// and a duration.
    ///
    /// The shape of the motion — outward, gravity-affected, decelerating — is
    /// what makes a burst read as physical rather than as an expanding ring.
    /// Deceleration uses a square-root curve, which is what a physical projectile
    /// does and is therefore what the eye expects.
    ///
    /// - Parameters:
    ///   - seed: The particle's launch parameters.
    ///   - t: Seconds since the burst began.
    ///   - duration: The burst's total duration, which is also the longest
    ///     allowed lifetime; longer-lived particles get clamped to it.
    ///   - size: The square's edge length. Particles travel a fraction of it, so
    ///     the burst scales with whatever view it is placed in.
    ///   - travel: How far a particle may get, as a fraction of `size`.
    static func at(seed: ParticleSeed, t: Double, duration: Double, size: CGFloat, travel: Double) -> ParticlePoint {
        guard duration > 0, t.isFinite else { return ParticlePoint(x: 0, y: 0, opacity: 0, scale: 0) }

        let clampedLife = max(0.01, min(seed.life * duration, duration))
        let progress = min(max(t / clampedLife, 0), 1)

        // Square-root deceleration: fast at launch, settling as it fades.
        let reach = travel * sqrt(progress) * seed.speedScale
        let distance = reach * Double(size)

        let cosA = cos(seed.angle)
        let sinA = sin(seed.angle)
        var x = cosA * distance
        // Gravity pulls down, scaled by how horizontal the particle launched, so
        // an upward particle arcs and a sideways one droops — which is what makes
        // the burst look thrown rather than inflated.
        var y = sinA * distance + (0.32 * distance * progress * progress)

        // Clamp inside the canvas. A particle that flies out of bounds leaves a
        // clipped, ugly edge on a celebration, and these are all drawn inside a
        // rounded frame.
        let limit = Double(size) * 0.5
        x = min(max(x, -limit), limit)
        y = min(max(y, -limit), limit)

        return ParticlePoint(
            x: x,
            y: y,
            // Hold, then fall away fast: `progress^1.6` keeps the particle
            // visible through the readable part of its flight.
            opacity: 1 - pow(progress, 1.6),
            scale: max(0, 1 - 0.55 * progress)
        )
    }
}