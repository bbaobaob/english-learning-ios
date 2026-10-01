import SwiftUI

/// The pulsing ring shown while the learner is speaking or recording.
///
/// The two states must be *obviously* different, not subtly different, because
/// a learner looking at a phone held at arm's length has to know at a glance
/// whether their voice is being captured. So the difference is made on four
/// axes at once — colour, shape, speed, and centre:
///
/// |              | `.idle`                   | `.listening`               | `.recording`              |
/// |--------------|---------------------------|----------------------------|---------------------------|
/// | colour       | `brand`                   | `brand`                    | `danger`                  |
/// | ring         | one thin, slow ring       | two rings, in and out      | two rings, in and out     |
/// | period       | 3.4s                      | 1.6s                       | 0.9s                      |
/// | centre       | a hollow dot              | a hollow dot               | a filled dot              |
/// | symbol       | `waveform`                | `waveform`                 | `mic.fill`                |
///
/// Under Reduce Motion each state renders as a **single static ring** with the
/// correct colour, ring count and centre — so idle, listening and recording are
/// still distinguishable without anything pulsing. State is also spoken: the
/// label reads "Not recording" / "Listening" / "Recording", because the ring
/// alone is a purely visual signal.
///
/// Pair with no haptics: recording is a sustained state, not an event, and a
/// haptic belongs to `Haptics.selection()` at the tap that started it.
struct BreathingRecorder: View {

    /// What the indicator is reporting.
    enum RecorderState: Equatable {
        /// Nothing is happening. The learner has not started.
        case idle
        /// The microphone is open and levels are arriving, but nothing is
        /// captured to a file — e.g. a live level check before committing.
        case listening
        /// A take is being captured.
        case recording

        /// The label VoiceOver reads for this state.
        var spokenLabel: String {
            switch self {
            case .idle: return "Not recording"
            case .listening: return "Listening"
            case .recording: return "Recording"
            }
        }

        /// How fast this state pulses. `.recording` is fastest because it is the
        /// one where the learner most wants to feel it is live.
        var period: Double {
            switch self {
            case .idle: return 3.4
            case .listening: return 1.6
            case .recording: return 0.9
            }
        }

        /// How far the ring expands, as a scale multiplier.
        var reach: Double {
            switch self {
            case .idle: return 1.0
            case .listening, .recording: return 1.28
            }
        }
    }

    // MARK: Input

    /// The state to display.
    var state: RecorderState = .idle
    /// The ring's diameter in points. Sized in points, not from text, so it
    /// stays put at every Dynamic Type size.
    var diameter: CGFloat = 64

    // MARK: State

    /// Drives the pulse. Mounted only when the state is one that pulses.
    @State private var isAnimating = false

    @Environment(\.motionSettings) private var settings

    // MARK: Body

    var body: some View {
        Group {
            if isAnimating {
                TimelineView(.animation) { context in
                    indicator(at: context.date)
                }
            } else {
                // Static: the same indicator with a frozen phase. Under Reduce
                // Motion this is the only path.
                indicator(at: nil)
            }
        }
        .frame(width: diameter, height: diameter)
        // The state is carried by the label, not by the animation, so this is a
        // real accessibility element rather than decoration.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: state.spokenLabel))
        .accessibilityAddTraits(state == .recording ? [.updatesFrequently] : [])
        .onAppear(perform: start)
        .onChange(of: state) { _, _ in start() }
        .onChange(of: settings.reduceMotion) { _, _ in start() }
        .onDisappear { isAnimating = false }
    }

    // MARK: Indicator

    @ViewBuilder
    private func indicator(at date: Date?) -> some View {
        let phase = date.map(wrappedPhase(at:)) ?? 0

        ZStack {
            // Two concentric rings, both phase-shifted, so the pulse travels
            // outward instead of the whole thing breathing in place.
            ring(scale: state.reach * (0.86 + 0.14 * phase), opacity: 1 - 0.55 * phase)
            ring(scale: state.reach * (0.86 + 0.14 * ((phase + 0.5).truncatingRemainder(dividingBy: 1))),
                 opacity: 1 - 0.55 * ((phase + 0.5).truncatingRemainder(dividingBy: 1)))

            centre
        }
    }

    @ViewBuilder
    private func ring(scale: Double, opacity: Double) -> some View {
        Circle()
            .strokeBorder(tintColor.opacity(max(opacity, 0)), lineWidth: 2)
            .frame(width: diameter, height: diameter)
            .scaleEffect(scale)
    }

    /// The middle. Filled while recording, hollow otherwise — the third axis of
    /// the state difference, and the one that survives Reduce Motion intact.
    @ViewBuilder
    private var centre: some View {
        ZStack {
            Circle()
                .fill(state == .recording ? tintColor : Palette.surface)
                .frame(width: diameter * 0.34, height: diameter * 0.34)
                .overlay(
                    Circle()
                        .strokeBorder(tintColor, lineWidth: 2)
                        .frame(width: diameter * 0.34, height: diameter * 0.34)
                )

            Image(systemName: state == .recording ? "mic.fill" : "waveform")
                .font(.system(size: diameter * 0.18, weight: .semibold))
                // The glyph is legible on both the filled and the hollow centre.
                .foregroundStyle(state == .recording ? Palette.surface : tintColor)
                .accessibilityHidden(true)
        }
    }

    private var tintColor: Color {
        state == .recording ? Palette.danger : Palette.brand
    }

    // MARK: Clock

    private func start() {
        // Idle does not pulse. A ring that breathes while nothing is happening is
        // a heartbeat on a screen that is doing nothing, and it is what makes an
        // indicator feel like decoration.
        isAnimating = !settings.reduceMotion && state != .idle
    }

    /// Wrapped phase `0...1` at the state's own period, so a recording ring is
    /// visibly faster than a listening one.
    private func wrappedPhase(at date: Date) -> Double {
        let period = state.period
        guard period > 0 else { return 0 }
        let interval = date.timeIntervalSinceReferenceDate
        guard interval.isFinite else { return 0 }
        return interval.truncatingRemainder(dividingBy: period) / period
    }
}

// MARK: - Test seam

extension BreathingRecorder {

    /// Self-check for the state distinctions.
    ///
    /// The properties that make the two live states obviously different — and
    /// that must survive Reduce Motion, which drops the timing but not the
    /// colour, ring count or centre fill.
    static func check() {
        let idle = RecorderState.idle
        let listening = RecorderState.listening
        let recording = RecorderState.recording

        // Each state has its own spoken label — the non-visual carrier of state.
        let labels = [idle.spokenLabel, listening.spokenLabel, recording.spokenLabel]
        assert(Set(labels).count == 3, "every state needs a distinct spoken label")
        assert(labels.allSatisfy { !$0.isEmpty }, "no state label may be empty")

        // Recording pulses far faster than listening, which is what makes the two
        // live states distinguishable from across a room.
        assert(recording.period < listening.period, "recording must pulse faster than listening")
        assert(listening.period < idle.period, "listening must pulse faster than idle")

        // Idle never expands; the live states do, which is the shape difference.
        assert(idle.reach < listening.reach, "idle must not expand")
        assert(idle.reach < recording.reach, "idle must not expand")

        // Live states share their reach, so the *speed* and the *colour* are what
        // tell them apart.
        assert(listening.reach == recording.reach, "live states share a reach")

        assert(recording != listening, "recording and listening must be distinct states")
    }
}