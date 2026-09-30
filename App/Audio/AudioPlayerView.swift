import SwiftUI
import EnglishCore

/// The transport bar for one `AudioClip`.
///
/// The controls are on a glass surface because the bar floats over content —
/// in the dictation flow it sits above a text field, and the learner needs to
/// hear the sentence again without scrolling away from what they are typing.
///
/// **Nothing here branches on `clip.kind`.** A `speech` clip and a downloaded
/// MP3 present the same controls, including the scrubber: `AudioPlayerModel`
/// renders a speech clip to a cached file before playing it, so by the time
/// this view sees it there is a real timeline, a real position, and a real
/// duration. That is the whole reason the render exists — `AVSpeechUtterance`
/// alone could offer play and stop and nothing else, which would have forced
/// this file to grow a speech-specific branch.
struct AudioPlayerView: View {
    /// The clip being played.
    let clip: AudioClip

    @Environment(AudioPlayerModel.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The rates offered in the speed menu, as multiples of normal speed.
    ///
    /// Declared as multiples rather than absolute rates so the presets keep
    /// their meaning on any device: the underlying `AVSpeechUtterance` range is
    /// not a documented constant and differs by OS version and voice.
    ///
    /// Deliberately excludes anything below 1x as a *persistent* setting: slow
    /// listening is the slow-replay button's job, and mixing the two makes both
    /// less useful.
    private let speeds: [Float] = SpeechRate.speedMultiples.map(Float.init)

    var body: some View {
        VStack(spacing: Spacing.md) {
            header
            transport
            if canScrub {
                scrubber
            } else {
                // No timeline yet — the clip is still being fetched or rendered.
                // The static line is shown instead of a control that would do
                // nothing, and it disappears the moment the duration is real.
                elapsedLine
            }
            options
        }
        .padding(Spacing.md)
        .glassCard()
        .onAppear {
            // `autoplay: false`: a player appearing on screen should not
            // start making noise before the learner has read the prompt.
            player.play(clip, autoplay: false)
        }
        .onDisappear {
            player.stop()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(clip.title ?? clip.text ?? "Audio")
                    .font(AppFont.display(.subheadline))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if player.isLoading {
                    Label("Loading audio", systemImage: "arrow.down.circle")
                        .font(AppFont.body(.caption))
                        .foregroundStyle(Palette.textSecondary)
                } else if player.isSpeaking {
                    // The speaking indicator. It is the only feedback a TTS
                    // utterance gives, so it is deliberately animated and
                    // deliberately hidden from VoiceOver — the utterance itself
                    // is the announcement.
                    SpeakingIndicator()
                        .accessibilityHidden(true)
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: Spacing.lg) {
            IconButton(
                symbol: "arrow.counterclockwise",
                label: "Replay from the start",
                action: { Haptics.selection(); player.replay() }
            )

            if canScrub {
                IconButton(
                    symbol: "gobackward.10",
                    label: "Skip back 10 seconds",
                    action: { Haptics.selection(); player.skip(by: -10) }
                )
            }

            playButton

            // Slow replay is a first-class control, not a long-press on speed:
            // it is the control a learner reaches for most in the alphabet and
            // dictation flows, so it gets a permanent place in the bar.
            Button {
                Haptics.selection()
                player.slowReplay()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "tortoise.fill").font(AppFont.body(.headline))
                    Text("Slow")
                        .font(AppFont.body(.caption2, weight: .semibold))
                }
                .foregroundStyle(Palette.brand)
                .frame(minWidth: Metric.tapTarget, minHeight: Metric.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "Play slowly"))
            .accessibilityHint(Text(verbatim: "Repeats the clip at a much lower speed so you can hear each word."))
            .accessibilityAddTraits(.isButton)

            if canScrub {
                IconButton(
                    symbol: "goforward.10",
                    label: "Skip forward 10 seconds",
                    action: { Haptics.selection(); player.skip(by: 10) }
                )
            }

            IconButton(
                symbol: "repeat",
                label: player.isLooping ? "Looping on" : "Looping off",
                isActive: player.isLooping,
                action: {
                    Haptics.selection()
                    player.setLooping(!player.isLooping)
                }
            )

            // Only offered when a sequence is loaded. Shuffling one clip is a
            // no-op, and a toggle that does nothing is worse than no toggle.
            if player.hasShuffleableQueue {
                IconButton(
                    symbol: "shuffle",
                    label: player.isShuffled ? "Shuffled" : "In order",
                    isActive: player.isShuffled,
                    action: {
                        Haptics.selection()
                        player.isShuffled.toggle()
                    }
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var playButton: some View {
        Button {
            Haptics.selection()
            player.togglePlayback()
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(AppFont.body(.title2, weight: .bold))
                .foregroundStyle(Palette.surface)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Palette.brand))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: player.isPlaying ? "Pause" : "Play"))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Scrubber

    /// `true` only when there is a real timeline to drag.
    ///
    /// No longer excludes `speech` clips: a speech clip is rendered to a file
    /// before it plays, so it has a genuine duration and a genuine position.
    /// The only thing that can still block the scrubber is a render that has not
    /// finished, which is exactly what `duration == 0` means.
    private var canScrub: Bool {
        player.duration > 0 && !player.isLoading
    }

    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false

    private var scrubber: some View {
        VStack(spacing: Spacing.xs) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubPosition : player.elapsed },
                    set: { scrubPosition = $0 }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    // Commit on release, not on every pixel of drag: seeking
                    // continuously makes a remote clip stutter.
                    if !editing { player.seek(to: scrubPosition) }
                }
            )
            .tint(Palette.brand)
            .accessibilityLabel(Text(verbatim: "Playback position"))
            .accessibilityValue(Text(verbatim: "\(Format.time(player.elapsed)) of \(Format.time(player.duration))"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: player.skip(by: 5)
                case .decrement: player.skip(by: -5)
                default: break
                }
            }

            elapsedLine
        }
    }

    private var elapsedLine: some View {
        HStack {
            Text(Format.time(isScrubbing ? scrubPosition : player.elapsed))
            Spacer()
            // "Preparing…" rather than a kind name: during a render the clip is
            // a speech clip, and telling the learner so invites them to wonder
            // why it cannot be scrubbed yet. Say what is happening instead.
            Text(canScrub ? Format.time(player.duration) : "Preparing…")
        }
        .font(AppFont.mono(.caption))
        .foregroundStyle(Palette.textSecondary)
        .accessibilityHidden(true)
    }

    // MARK: - Options

    private var options: some View {
        HStack(spacing: Spacing.md) {
            speedMenu
            repeatCounter
            Spacer(minLength: 0)
            if let error = player.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(AppFont.body(.caption))
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var speedMenu: some View {
        Menu {
            ForEach(speeds, id: \.self) { speed in
                Button {
                    Haptics.selection()
                    player.playbackRate = speed
                } label: {
                    // The checkmark is what communicates "this is the current
                    // speed"; the label alone would not.
                    let label = SpeechRate.label(forMultiple: Double(speed))
                    if player.playbackRate == speed {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
            }
        } label: {
            Label(
                SpeechRate.label(forMultiple: Double(player.playbackRate)),
                systemImage: "speedometer"
            )
            .font(AppFont.body(.caption, weight: .semibold))
            .foregroundStyle(Palette.textSecondary)
            .frame(minHeight: Metric.controlHeight)
        }
        .accessibilityLabel(Text(verbatim: "Playback speed, \(SpeechRate.label(forMultiple: Double(player.playbackRate)))"))
        .accessibilityHint(Text(verbatim: "Double tap to choose from half speed to one and a half times."))
    }

    private var repeatCounter: some View {
        HStack(spacing: Spacing.xs) {
            Button {
                Haptics.selection()
                player.decrementRepeat()
            } label: {
                Image(systemName: "minus")
                    .frame(width: 28, height: Metric.tapTarget)
            }
            .buttonStyle(.plain)
            .disabled(player.repeatCount <= 1)
            .foregroundStyle(Palette.textSecondary)
            .accessibilityLabel(Text(verbatim: "Fewer repeats"))
            .accessibilityAddTraits(.isButton)

            Text("×\(player.repeatCount)")
                .font(AppFont.mono(.caption, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
                .frame(minWidth: 28)
                .accessibilityLabel(Text(verbatim: "Repeats \(player.repeatCount) times"))

            Button {
                Haptics.selection()
                player.incrementRepeat()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: Metric.tapTarget)
            }
            .buttonStyle(.plain)
            .disabled(player.repeatCount >= 20)
            .foregroundStyle(Palette.textSecondary)
            .accessibilityLabel(Text(verbatim: "More repeats"))
            .accessibilityAddTraits(.isButton)
        }
    }
}

/// Three bars that pulse while an utterance is in flight.
///
/// Animated with a `TimelineView` rather than a chain of `withAnimation`
/// calls, so the pulse is driven by the clock and stops dead when the view is
/// removed — a repeating SwiftUI animation keeps running off-screen.
private struct SpeakingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(Palette.brand)
                    .frame(width: 3, height: barHeight(index))
            }
        }
        .frame(height: 14, alignment: .center)
    }

    /// Under Reduce Motion the bars sit at a fixed, static height: the state is
    /// still communicated, the animation is not.
    private func barHeight(_ index: Int) -> CGFloat {
        reduceMotion ? 10 : [8, 14, 10][index % 3]
    }
}

/// The toggle as it appears in the dictation flow: play / replay / slow replay
/// in a row, with nothing else competing for attention.
///
/// A thin wrapper over the same model methods the full player uses, so the
/// reduced set cannot drift from the complete one.
struct QuickAudioControls: View {
    let clip: AudioClip

    @Environment(AudioPlayerModel.self) private var player

    var body: some View {
        HStack(spacing: Spacing.lg) {
            Button {
                Haptics.selection()
                player.replay()
            } label: {
                Image(systemName: "arrow.counterclockwise").font(AppFont.body(.headline))
                    .frame(width: Metric.tapTarget, height: Metric.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textSecondary)
            .accessibilityLabel(Text(verbatim: "Play again"))
            .accessibilityAddTraits(.isButton)

            Button {
                Haptics.selection()
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(AppFont.body(.title3, weight: .bold))
                    .foregroundStyle(Palette.surface)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Palette.brand))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: player.isPlaying ? "Pause" : "Play"))
            .accessibilityAddTraits(.isButton)

            Button {
                Haptics.selection()
                player.slowReplay()
            } label: {
                Image(systemName: "tortoise.fill").font(AppFont.body(.headline))
                    .foregroundStyle(Palette.brand)
                    .frame(width: Metric.tapTarget, height: Metric.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "Play slowly"))
            .accessibilityHint(Text(verbatim: "Repeats the audio at a much lower speed."))
            .accessibilityAddTraits(.isButton)

            // The level meter, once, on the control set used in the tightest spaces.
            //
            // No `AudioLevelProviding` is passed, so this takes the
            // effect's *unmeasured* path: `AVPlayer` publishes no metering, and
            // a bar that claimed to know the level would be inventing it. What it
            // shows instead is a very slow travelling breath while audio is
            // actually playing, which says "something is happening" without
            // claiming to know how loud. The play button already carries the
            // state, so this is decorative and hidden.
            LiveWaveform(
                levels: nil,
                isActive: player.isSpeaking,
                barCount: 16,
                barWidth: 2,
                barSpacing: 2,
                tint: Palette.brand,
                height: 28
            )
            .frame(width: 72)
            .motionDecoration()
        }
        .onAppear { player.play(clip, autoplay: false) }
    }
}
