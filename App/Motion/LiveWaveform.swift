import SwiftUI

/// A level meter drawn as bars, driven by **real** audio metering.
///
/// This is the effect most likely to lie, so its first rule is that it only
/// moves when something is genuinely producing sound. Four states, all
/// reachable, all distinct on screen:
///
///   * **Idle.** No audio and no provider: a flat baseline of equal bars.
///     Unmoved, unanimated, no timeline running.
///   * **Silent.** A provider reporting a real `0`: also flat. A playing-but-
///     silent clip looks silent, because it is.
///   * **Active.** A provider reporting a real level: the bars track it.
///   * **Unmeasured.** Something is playing but no level exists — the TTS case,
///     where `AVSpeechSynthesizer` publishes no metering at all. Here the
///     baseline gets a *very* slight, slow travelling breath. A whisper of
///     motion says "something is happening"; a fabricated bar would claim to
///     know how loud. The second is a lie and the first is not.
///
/// **Wiring.** Pass an `AudioLevelProviding`:
/// ```swift
/// // A rendered file, genuinely metered:
/// MeteredPlayerLevels(player: player)   →  LiveWaveform(levels: meter, isActive: true)
///
/// // Speech, genuinely unmeasurable:
/// LiveWaveform(isActive: speech.isSpeaking)   // renders the unmeasured breath
/// ```
/// The view polls the provider itself at 20 Hz with a cancellable task — the
/// provider is an existential, so SwiftUI cannot observe it, and polling is
/// also what a meter does. The task is cancelled on disappear.
///
/// **Under Reduce Motion** every state renders its static form with no timeline
/// and no polling: the bars hold their last real height. The level is still
/// conveyed by bar *height*, so the information survives — it just does not
/// move. Under Reduce Transparency the bars are solid rather than translucent.
struct LiveWaveform: View {

    // MARK: Input

    /// A real metering source. `nil` means no level is genuinely available.
    var levels: (any AudioLevelProviding)?

    /// Whether audio is actually playing. Drives the unmeasured state, and is
    /// the only thing allowed to move anything when `levels` is `nil`.
    var isActive: Bool = false

    /// Number of bars. More than about 40 is a solid block at any sane width.
    var barCount: Int = 28
    /// Bar width in points.
    var barWidth: CGFloat = 3
    /// Gap between bars.
    var barSpacing: CGFloat = 3
    /// The bars' colour.
    var tint: Color = Palette.brand
    /// Height of the meter at full level.
    var height: CGFloat = 32

    // MARK: State

    /// A bounded history of real levels, oldest first. Bounded so the array
    /// cannot grow without limit during a long clip.
    @State private var history: [Double] = []
    /// Whether the unmeasured breath is running.
    @State private var isBreathing = false
    /// The polling task. Cancelled on disappear and whenever polling stops.
    @State private var poller: Task<Void, Never>?

    @Environment(\.motionSettings) private var settings

    /// ponytail: 48 samples is ~2.4s at 20Hz, enough to read as a waveform.
    /// Raise it only if a level source reports more slowly than 20Hz.
    private let historyLimit = 48
    /// Poll interval in seconds. 20Hz.
    private let pollInterval: Double = 0.05
    /// The shortest bar, as a fraction of full height. A meter that vanishes at
    /// quiet volumes is worse than one that never quite reaches zero.
    private let baseline: Double = 0.06

    // MARK: Body

    var body: some View {
        Group {
            if needsAnimation {
                TimelineView(.animation) { context in
                    bars(at: context.date)
                }
            } else {
                // The resting path. No timeline mounted, so nothing ticks — and
                // this is the state a waveform is in for most of a lesson.
                bars(at: nil)
            }
        }
        .frame(height: height)
        .motionDecoration()
        .onAppear(perform: start)
        .onChange(of: isActive) { _, _ in start() }
        .onChange(of: settings.reduceMotion) { _, _ in start() }
        .onDisappear(perform: stop)
        // The waveform is decorative, but its state is not, so the state is
        // spoken. A VoiceOver user gets "Playing" or "No audio", not silence.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Audio level"))
        .accessibilityValue(Text(verbatim: spokenState))
    }

    // MARK: State machine

    /// Whether a timeline is warranted.
    ///
    /// Reduce Motion: never. The bars hold their real heights.
    private var needsAnimation: Bool {
        guard !settings.reduceMotion else { return false }
        // A real level re-renders through `history`; no timeline needed.
        if hasRealLevel { return false }
        // Unmeasured but playing: the slow travelling breath.
        return isActive && isBreathing
    }

    private var hasRealLevel: Bool {
        guard let level = latestLevel else { return false }
        return level.isFinite
    }

    private var latestLevel: Double? {
        history.last
    }

    private var spokenState: String {
        guard isActive else { return "No audio playing" }
        guard let level = latestLevel, level.isFinite else { return "Playing" }
        return "Playing, level \(Format.percent(level))"
    }

    // MARK: Lifecycle

    private func start() {
        // The breath only ever runs in the unmeasured state, and never under
        // Reduce Motion.
        isBreathing = !settings.reduceMotion && isActive && !hasRealLevel

        guard !settings.reduceMotion else {
            poller?.cancel()
            poller = nil
            return
        }

        guard let levels else {
            poller?.cancel()
            poller = nil
            if !isActive { history.removeAll() }
            return
        }

        // A cancellable task rather than a `Timer`: it is torn down with the
        // view and cannot survive the screen.
        poller?.cancel()
        poller = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.ingest(levels.currentLevel)
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    private func stop() {
        poller?.cancel()
        poller = nil
        isBreathing = false
        history.removeAll()
    }

    /// Records one real level.
    ///
    /// A `nil` level is *not* zero. Zero means silence, which is a fact; `nil`
    /// means "not measurable here", which is a different fact, and the bar
    /// heights below treat them differently.
    private func ingest(_ level: Double?) {
        guard let level, level.isFinite else {
            // No real level this tick: fall back to the unmeasured state if
            // something is playing.
            isBreathing = !settings.reduceMotion && isActive
            return
        }
        isBreathing = false
        history.append(min(max(level, 0), 1))
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }

    // MARK: Drawing

    @ViewBuilder
    private func bars(at date: Date?) -> some View {
        Canvas { context, size in
            let values = barHeights(at: date)
            let slot = barWidth + barSpacing
            // Centre the run of bars in the available width.
            let originX = max(0, (size.width - slot * CGFloat(values.count)) / 2)
            let midY = size.height / 2

            // A plain `for` over a local array: no allocation per frame beyond
            // the array itself, which the closure does not build.
            for (index, value) in values.enumerated() {
                let barHeight = max(2, size.height * CGFloat(value))
                let x = originX + CGFloat(index) * slot
                let rect = CGRect(
                    x: x,
                    y: midY - barHeight / 2,
                    width: barWidth,
                    height: barHeight
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(barColor(opacity: barOpacity(for: value)))
                )
            }
        }
    }

    /// The bar height for each slot, `0...1`, oldest sample first.
    ///
    /// Under Reduce Motion the history is simply frozen — the bars keep their
    /// real heights and stop moving, which is the honest reduced form.
    private func barHeights(at date: Date?) -> [Double] {
        let count = max(1, barCount)

        if !history.isEmpty {
            // Fewer samples than bars leaves the leading bars at the baseline,
            // which is what a filling meter should look like.
            let leading = max(0, count - history.count)
            let tail = history.suffix(count).map { max($0, baseline) }
            return Array(repeating: baseline, count: leading) + tail
        }

        if isActive, isBreathing, !settings.reduceMotion, let date {
            let phase = unmeasuredPhase(at: date)
            return (0..<count).map { index in
                // A slow travelling wave, not a uniform pulse, so it reads as
                // ambiguous rather than as data. Amplitude is tiny by design.
                let offset = Double(index) / Double(count)
                let local = 0.5 + 0.5 * sin((phase + offset) * 2 * .pi)
                return baseline + 0.05 * local
            }
        }

        // Idle: flat. Every bar identical, which is the honest picture of no
        // audio.
        return Array(repeating: baseline, count: count)
    }

    /// Wrapped phase for the unmeasured breath, `0...1`.
    private func unmeasuredPhase(at date: Date) -> Double {
        let period: Double = 2.6
        guard period > 0 else { return 0 }
        let interval = date.timeIntervalSinceReferenceDate
        guard interval.isFinite else { return 0 }
        return interval.truncatingRemainder(dividingBy: period) / period
    }

    private func barColor(opacity: Double) -> Color {
        settings.reduceTransparency ? tint : tint.opacity(opacity)
    }

    /// Older samples fade, so "now" is the brightest bar and the eye can find it
    /// without reading a number.
    private func barOpacity(for value: Double) -> Double {
        guard !settings.reduceTransparency else { return 1 }
        return min(max(0.35 + value * 0.65, 0.35), 1)
    }
}

// MARK: - Test seam

/// The bar-height policy behind ``LiveWaveform``, as pure functions.
enum WaveformHeights {
    /// The bar heights for the three static states.
    static func idle(bars: Int, baseline: Double) -> [Double] {
        Array(repeating: baseline, count: max(1, bars))
    }

    /// Bars for a real history, oldest first, padded at the baseline.
    static func metered(history: [Double], bars: Int, baseline: Double) -> [Double] {
        let count = max(1, bars)
        guard !history.isEmpty else { return idle(bars: count, baseline: baseline) }
        let leading = max(0, count - history.count)
        let tail = history.suffix(count).map { max($0, baseline) }
        return Array(repeating: baseline, count: leading) + tail
    }
}

extension LiveWaveform {

    /// Self-check for the height policy.
    static func check() {
        // Idle: every bar identical.
        let idle = WaveformHeights.idle(bars: 8, baseline: 0.06)
        assert(idle.count == 8, "idle draws one bar per slot")
        assert(Set(idle.map { $0 < 0.0001 }).isEmpty, "idle bars are all equal")
        assert(idle.allSatisfy { $0 > 0 }, "a silent meter is still visible")

        // Zero bars still draws one — a collapsed meter is worse than a stub.
        assert(WaveformHeights.idle(bars: 0, baseline: 0.06).count == 1, "a zero bar count still draws one bar")

        // Fewer samples than bars: padded at the baseline, total is exact.
        let padded = WaveformHeights.metered(history: [0.5, 1.0], bars: 6, baseline: 0.06)
        assert(padded.count == 6, "the bar count never changes with history length")
        assert(padded[0] == 0.06 && padded[1] == 0.06, "leading bars sit at the baseline")
        assert(padded.last == 1.0, "the newest sample is the last bar")

        // More samples than bars: the newest `bars` win, oldest dropped.
        let trimmed = WaveformHeights.metered(history: [0.1, 0.2, 0.3, 0.4, 0.5], bars: 2, baseline: 0.06)
        assert(trimmed == [0.4, 0.5], "history is trimmed to the newest samples")

        // Empty history falls back to idle rather than to nothing.
        assert(WaveformHeights.metered(history: [], bars: 3, baseline: 0.06)
            == WaveformHeights.idle(bars: 3, baseline: 0.06),
               "no history reads as idle")

        // A level below the baseline is lifted to it, never drawn as zero.
        let quiet = WaveformHeights.metered(history: [0.0], bars: 1, baseline: 0.06)
        assert(quiet == [0.06], "a silent sample still draws a visible bar")
    }
}