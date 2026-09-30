import SwiftUI
import UIKit
import EnglishCore
import EnglishStore

/// Speaking practice that actually records.
///
/// The cue card comes from the speaking topic's own content — its `examples` steps give
/// a sentence and its Vietnamese translation, its `dictation` steps give a target
/// sentence with a hint. Nothing here is invented, and nothing is transcribed: the
/// learner records a take, plays it back, and compares it against the model, which is
/// spoken on demand through the app's speech service.
struct SpeakingDrillView: View {

    let level: Level

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var recorder = RecordingService()
    @State private var cardIndex = 0
    @State private var finished = false

    /// How long a part should take at each level. A calibration knob, not a grade:
    /// the view shows elapsed time against it and never penalises either way.
    private var targetSeconds: TimeInterval {
        switch level {
        case .beginner: 20
        case .intermediate: 35
        case .advanced: 60
        }
    }

    var body: some View {
        Group {
            if cards.isEmpty {
                EmptyStateView(
                    symbol: "mic",
                    title: "No speaking prompts",
                    message: "The speaking content for this level has no example or dictation sentences to work from.",
                    actionTitle: nil,
                    action: nil
                )
            } else if finished {
                summaryScreen
            } else {
                practiceScreen
            }
        }
        .background(PracticeBackdrop())
        .navigationTitle("Speaking · \(level.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { recorder.discard() }
    }

    // MARK: - Practice

    private var practiceScreen: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if recorder.errorMessage != nil {
                        ErrorBanner(message: recorder.errorMessage ?? "", retry: {
                            recorder.clearError()
                            Task { await recorder.requestPermission() }
                        })
                    }

                    progressStrip
                    cueCard
                    timer
                    controls
                    Color.clear.frame(height: Spacing.lg)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
            }

            floatingBar
        }
    }

    private var progressStrip: some View {
        HStack(spacing: Spacing.md) {
            Text("Part \(cardIndex + 1) of \(cards.count)")
                .font(AppFont.mono(12, .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: Spacing.xs)
            Text(level.displayName)
                .font(AppFont.display(12, .regular))
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    /// The prompt. English on top, Vietnamese underneath as the meaning cue.
    private var cueCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "quote.opening")
                    .foregroundStyle(Color.brandSoft)
                    .accessibilityHidden(true)
                Text(cards[cardIndex].prompt)
                    .font(AppFont.display(24, .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            if let meaning = cards[cardIndex].meaning, !meaning.isEmpty {
                Text(meaning)
                    .font(AppFont.display(16, .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let hint = cards[cardIndex].hint, !hint.isEmpty {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(Color.warning)
                        .accessibilityHidden(true)
                    Text(hint)
                        .font(AppFont.display(14, .regular))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            }

            Text("Aim for about \(PracticeFormat.clock(targetSeconds)).")
                .font(AppFont.display(13, .regular))
                .foregroundStyle(.tertiary)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// Elapsed time against the per-part target.
    private var timer: some View {
        VStack(spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(PracticeFormat.clock(recorder.elapsed))
                    .font(AppFont.mono(30, .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text("of \(PracticeFormat.clock(targetSeconds))")
                    .font(AppFont.display(14, .regular))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            GeometryReader { proxy in
                let fraction = min(1, recorder.elapsed / targetSeconds)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.brandSoft.opacity(0.2))
                    Capsule()
                        .fill(fraction >= 1 ? Color.warning : Color.brand)
                        .frame(width: fraction * proxy.size.width)
                }
            }
            .frame(height: 10)
            .animation(Motion.Curve.linear, value: recorder.elapsed)

            Text(recorder.elapsed >= targetSeconds
                 ? "Over the target — but a longer answer is a fuller answer."
                 : recorder.isRecording ? "Recording" : recorder.hasTake ? "Take ready" : "Not recording")
                .font(AppFont.display(12, .semibold))
                .foregroundStyle(recorder.isRecording ? Color.danger : Color.secondary)
        }
        .padding(Spacing.lg)
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Elapsed \(PracticeFormat.clock(recorder.elapsed)) of \(PracticeFormat.clock(targetSeconds))")
    }

    @ViewBuilder
    private var controls: some View {
        if recorder.permission == .denied {
            deniedPanel
        } else if recorder.permission == .undetermined {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("One permission, then you are set")
                    .font(AppFont.display(17, .bold))
                Text("English Learning needs the microphone so you can hear yourself. The recording is written to a temporary file and deleted when you leave this screen — nothing about your voice is saved.")
                    .font(AppFont.display(14, .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(
                    title: "Allow microphone",
                    symbol: "mic.fill",
                    isEnabled: true,
                    action: {
                        Haptics.selection()
                        Task { await recorder.requestPermission() }
                    }
                )
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        } else {
            recordingControls
        }
    }

    private var deniedPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Microphone is off", systemImage: "mic.slash.fill")
                .font(AppFont.display(17, .bold))
                .foregroundStyle(Color.danger)

            Text("Speaking practice needs the microphone, and iOS has it switched off for this app. You can turn it back on in Settings, or read the model sentence and practise out loud instead — the take is never saved either way.")
                .font(AppFont.display(14, .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.md) {
                PrimaryButton(
                    title: "Open Settings",
                    symbol: "gear",
                    isEnabled: true,
                    action: openSettings
                )
                SecondaryButton(
                    title: "Skip recording",
                    symbol: "forward.end",
                    action: { advance() }
                )
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var recordingControls: some View {
        VStack(spacing: Spacing.md) {
            // The record button turns into its own liveness indicator. A learner
            // holding the phone at arm's length has to know at a glance whether
            // their voice is being captured, so the ring differs on four axes at
            // once — colour, ring count, speed and centre — and the elapsed time
            // beside it is the same fact in a form VoiceOver can read.
            HStack(spacing: Spacing.md) {
                BreathingRecorder(
                    state: recorder.isRecording ? .recording : (recorder.hasTake ? .listening : .idle),
                    diameter: 40
                )
                // The ring is a purely visual signal, so it is given a label
                // rather than hidden. The elapsed time and the status line live
                // in `timer` above; repeating either here would give VoiceOver
                // the same fact twice.
                .accessibilityLabel(
                    recorder.isRecording ? "Recording" : (recorder.hasTake ? "Take ready" : "Not recording")
                )

                Spacer(minLength: 0)
            }

            HStack(spacing: Spacing.md) {
                if recorder.isRecording {
                    PrimaryButton(
                        title: "Stop",
                        symbol: "stop.fill",
                        isEnabled: true,
                        action: {
                            recorder.stopRecording()
                            Haptics.success()
                        }
                    )
                } else {
                    PrimaryButton(
                        title: recorder.hasTake ? "Re-record" : "Record",
                        symbol: "mic.fill",
                        isEnabled: true,
                        action: {
                            if recorder.startRecording() { Haptics.warning() }
                        }
                    )
                }
            }

            SecondaryButton(
                title: "Play my take",
                symbol: "play.fill",
                action: {
                    recorder.playTake()
                    Haptics.selection()
                }
            )
            .disabled(!recorder.hasTake)
            .opacity(recorder.hasTake ? 1 : 0.5)

            PrimaryButton(
                title: "Next part",
                symbol: "arrow.right",
                isEnabled: !recorder.isRecording,
                action: { advance() }
            )
        }
    }

    /// Floating bar: the model answer and a stop-listening escape.
    private var floatingBar: some View {
        HStack(spacing: Spacing.md) {
            SecondaryButton(
                title: "Model answer",
                symbol: "speaker.wave.2.fill",
                action: {
                    appState.speech.speak(cards[cardIndex].prompt, rate: SpeechRate.example) {}
                    Haptics.selection()
                }
            )
            SecondaryButton(
                title: "Stop",
                symbol: "stop.circle",
                action: {
                    appState.speech.stop()
                    Haptics.selection()
                }
            )
            .disabled(!appState.speech.isSpeaking)
            .opacity(appState.speech.isSpeaking ? 1 : 0.5)
        }
        .padding(Spacing.md)
        // Layout first, glass last.
        .practiceFloatingGlass(cornerRadius: Radius.pill)
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.md)
    }

    // MARK: - Summary

    private var summaryScreen: some View {
        VStack(spacing: Spacing.lg) {
            Spacer(minLength: 0)

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.brand)
                .accessibilityHidden(true)

            Text("That is the set.")
                .font(AppFont.display(28, .bold))
                .accessibilityAddTraits(.isHeader)
            Text("You worked through \(PracticeFormat.phrase(cards.count, "prompt", "prompts")). Nothing was stored — the last take is deleted the moment you leave.")
                .font(AppFont.display(15, .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)

            HStack(spacing: Spacing.md) {
                StatCard(
                    title: "Prompts",
                    value: PracticeFormat.count(cards.count),
                    caption: "at \(level.displayName.lowercased())",
                    symbol: "quote.bubble",
                    tint: .brand
                )
                StatCard(
                    title: "Takes",
                    value: "Discarded",
                    caption: "nothing was saved",
                    symbol: "trash",
                    tint: .success
                )
            }
            .padding(.horizontal, Spacing.lg)

            Spacer(minLength: 0)

            VStack(spacing: Spacing.md) {
                PrimaryButton(
                    title: "Practise again",
                    symbol: "arrow.clockwise",
                    isEnabled: true,
                    action: {
                        Haptics.selection()
                        cardIndex = 0
                        finished = false
                        recorder.discard()
                    }
                )
                SecondaryButton(
                    title: "Done",
                    symbol: "checkmark",
                    action: { dismiss() }
                )
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
    }

    // MARK: - Actions

    private func advance() {
        Haptics.selection()
        recorder.discard()
        if cardIndex + 1 < cards.count {
            cardIndex += 1
        } else {
            finished = true
            appState.speech.stop()
            recorder.clearError()
            // ponytail: XP is 0 because nothing grades a recording. The graded XP for
            // speaking comes from the speaking topic's exercises in MixedPracticeView;
            // inventing a per-take award here would be a second XP source the engine
            // does not know about. Registering the minute keeps the streak honest.
            appState.store.registerStudy(minutes: 1, xp: 0, kind: .speaking)
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Content

    /// The prompts for this level, built from the speaking topic's own steps.
    ///
    /// `examples` steps supply a sentence and its Vietnamese gloss; `dictation` steps
    /// supply a target sentence with a structural hint. Both are real content, and both
    /// are speakable, so the model answer is simply the prompt spoken aloud.
    private var cards: [SpeakingCue] {
        guard let topic = appState.library.allTopics.first(where: { $0.kind == .speaking }) else {
            return []
        }
        var result: [SpeakingCue] = []
        for lesson in topic.lessons where lesson.resolvedLevel(fallback: topic.level) == level {
            for step in lesson.steps {
                switch step {
                case .examples(let examples):
                    result += examples.examples.map {
                        SpeakingCue(prompt: $0.en, meaning: $0.vi, hint: $0.note)
                    }
                case .dictation(let dictation):
                    result += dictation.items.map {
                        SpeakingCue(prompt: $0.expectedText, meaning: $0.translation, hint: $0.hint)
                    }
                default:
                    continue
                }
            }
        }
        return result
    }
}

/// One speaking prompt: what to say, what it means, and the structural hint.
struct SpeakingCue: Identifiable, Hashable {
    let prompt: String
    let meaning: String?
    let hint: String?

    var id: String { prompt }
}
