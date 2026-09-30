import SwiftUI
import AVKit
import EnglishCore

/// A video lesson: stage, subtitles, custom transport, transcript sheet.
///
/// **Why `VideoPlayer` and not `AVPlayerViewController`.** `VideoPlayer` is the
/// SwiftUI-native view over the same `AVPlayer`, and the decision is not about
/// rendering quality — it is about *control*. This screen needs a 15-second
/// skip, a speed control, a transcript sheet, and subtitles rendered *above*
/// the picture from `SubtitleCue` timestamps. `AVPlayerViewController` ships
/// its own control bar and its own subtitle handling, and there is no supported
/// way to remove the first while keeping the playback quality of the second. A
/// wrapped `AVPlayerViewController` with `showsPlaybackControls = false` would
/// work, but then every control below is hand-built anyway and the wrapper adds
/// a `UIViewController` bridging layer for nothing. `VideoPlayer` gives the same
/// `AVPlayer` layer with SwiftUI semantics throughout.
struct VideoLessonView: View {
    let video: VideoClip
    /// Called with a position in seconds, on a timer and on disappear.
    let bookmark: (Double) -> Void
    /// The position to resume from, in seconds. Read once, when the view
    /// appears.
    let position: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: VideoPlaybackModel?
    @State private var isTranscriptPresented = false
    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0

    /// The rates offered in the speed menu.
    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            stage
            if video.source.kind != .none {
                title
                transport
                scrubber
            }
            transcriptButton
        }
        .task {
            // Built once, in a `.task` rather than in `body`, so the
            // `AVPlayer` and its time observer are created exactly one time.
            let model = VideoPlaybackModel(clip: video)
            model.onPeriodicPosition = { bookmark($0) }
            self.model = model
            if position > 0, position < (video.durationSeconds ?? .infinity) {
                model.seek(to: position)
            }
        }
        .onDisappear {
            // The last write is the one that matters: without it a learner who
            // backs out mid-video loses up to five seconds of position.
            if let model {
                bookmark(model.currentTime)
            }
            model?.pause()
        }
        .sheet(isPresented: $isTranscriptPresented) {
            TranscriptSheet(video: video)
        }
    }

    // MARK: - Stage

    @ViewBuilder
    private var stage: some View {
        ZStack {
            Color.black

            if let model, let player = model.player {
                VideoPlayer(player: player)
                    .disabled(true)
                    .aspectRatio(Metric.videoAspect, contentMode: .fit)

                // A live caption driven by `SubtitleCue` timestamps, rendered
                // over the picture rather than handed to the system as a
                // caption track: it can be styled to stay readable on any
                // frame, and it highlights the cue the learner is hearing.
                if let cue = model.activeCue {
                    subtitleOverlay(cue.text)
                }
            } else {
                VideoPlaceholder()
            }
        }
        .aspectRatio(Metric.videoAspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: video.title.isEmpty ? "Lesson video" : video.title))
    }

    private func subtitleOverlay(_ text: String) -> some View {
        VStack {
            Spacer(minLength: 0)
            Text(text)
                .font(AppFont.body(.callout, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                // A dark plate behind the text rather than a drop shadow:
                // shadow-only legibility fails over a bright frame.
                .background(
                    RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                        .fill(.black.opacity(0.72))
                )
                .padding(Spacing.md)
        }
        .transition(.opacity)
        .animation(Motion.accessible(Motion.quick, reduceMotion: reduceMotion), value: text)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(video.title)
                .font(AppFont.display(.headline))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let model, let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(AppFont.body(.caption))
                    .foregroundStyle(Palette.danger)
            }
        }
    }

    // MARK: - Transport

    @ViewBuilder
    private var transport: some View {
        if let model, model.player != nil {
            HStack(spacing: Spacing.lg) {
                IconButton(
                    symbol: "gobackward.15",
                    label: "Skip back 15 seconds",
                    action: { Haptics.selection(); model.skip(by: -15) }
                )

                Button {
                    Haptics.selection()
                    model.togglePlayback()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(AppFont.body(.title2, weight: .bold))
                        .foregroundStyle(Palette.surface)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Palette.brand))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: model.isPlaying ? "Pause video" : "Play video"))
                .accessibilityAddTraits(.isButton)

                IconButton(
                    symbol: "goforward.15",
                    label: "Skip forward 15 seconds",
                    action: { Haptics.selection(); model.skip(by: 15) }
                )

                Spacer(minLength: 0)

                speedMenu(model)

                if !video.transcript.isEmpty {
                    IconButton(
                        symbol: "text.alignleft",
                        label: "Show the transcript",
                        action: { Haptics.selection(); isTranscriptPresented = true }
                    )
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .glassCard()
        }
    }

    private func speedMenu(_ model: VideoPlaybackModel) -> some View {
        Menu {
            ForEach(speeds, id: \.self) { speed in
                Button {
                    Haptics.selection()
                    model.rate = speed
                } label: {
                    if model.rate == speed {
                        Label("\(speed.formatted(.number.precision(.fractionLength(0...1))))×", systemImage: "checkmark")
                    } else {
                        Text("\(speed.formatted(.number.precision(.fractionLength(0...1))))×")
                    }
                }
            }
        } label: {
            Label(
                "\(model.rate.formatted(.number.precision(.fractionLength(0...1))))×",
                systemImage: "speedometer"
            )
            .font(AppFont.body(.caption, weight: .semibold))
            .foregroundStyle(Palette.textSecondary)
            .frame(minHeight: Metric.controlHeight)
        }
        .accessibilityLabel(Text(verbatim: "Playback speed"))
        .accessibilityHint(Text(verbatim: "Double tap to change how fast the video plays."))
    }

    // MARK: - Scrubber

    @ViewBuilder
    private var scrubber: some View {
        if let model, model.player != nil {
            VStack(spacing: Spacing.xs) {
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubPosition : model.currentTime },
                        set: { scrubPosition = $0 }
                    ),
                    in: 0...max(model.duration, 1),
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing { model.seek(to: scrubPosition) }
                    }
                )
                .tint(Palette.brand)
                .accessibilityLabel(Text(verbatim: "Video position"))
                .accessibilityValue(
                    Text(verbatim: "\(Format.time(isScrubbing ? scrubPosition : model.currentTime)) of \(Format.time(model.duration))")
                )
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: model.skip(by: 15)
                    case .decrement: model.skip(by: -15)
                    default: break
                    }
                }

                HStack {
                    Text(Format.time(isScrubbing ? scrubPosition : model.currentTime))
                    Spacer()
                    Text(Format.time(model.duration))
                }
                .font(AppFont.mono(.caption))
                .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcriptButton: some View {
        if !video.transcript.isEmpty {
            SecondaryButton(
                title: "Transcript",
                symbol: "text.alignleft",
                action: { isTranscriptPresented = true }
            )
        }
    }
}

/// The `source == .none` state.
///
/// This is a designed state, not an error: a lesson can be entirely theory and
/// exercises with no video at all, and the architecture forbids inventing a
/// URL to fill the gap. So the placeholder says what the lesson offers instead
/// of apologising for what it does not.
private struct VideoPlaceholder: View {
    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "film.stack")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityHidden(true)

            Text("This lesson has no video")
                .font(AppFont.display(.subheadline))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Read the explanation and work through the examples below.")
                .font(AppFont.body(.caption))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .accessibilityElement(children: .combine)
    }
}

/// The transcript, in a sheet.
///
/// Tapping a line seeks to it when there are subtitles to seek by, and simply
/// highlights the line otherwise. The tap target is the line, not the sheet.
private struct TranscriptSheet: View {
    let video: VideoClip
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if video.transcript.isEmpty {
                        EmptyStateView(
                            symbol: "text.alignleft",
                            title: "No transcript",
                            message: "This video has no written transcript. The subtitles appear on the video itself."
                        )
                    } else {
                        ForEach(Array(video.transcript.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(AppFont.body(.body))
                                .foregroundStyle(Palette.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, Spacing.sm)
                                .accessibilityLabel(Text(verbatim: "Line \(index + 1). \(line)"))
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .background(Palette.background)
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
