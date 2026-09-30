import EnglishCore
import SwiftUI
import UIKit

/// Speaking practice for Parts 1, 2 and 3.
///
/// Recording is real: `AVAudioRecorder` in, `AVAudioPlayer` out, the take deleted when
/// the screen goes away. Permission is asked for on the first record tap and nowhere
/// else, and a refusal gets an explanation and a link to Settings rather than a dead button.
struct SpeakingPracticeView: View {
    let lesson: IELTSPaperLesson

    @Environment(AppState.self) private var appState

    @State private var recorder = RecordingService()
    @State private var showRubric = false
    @State private var showModelAnswer = false
    @State private var hasAppeared = false

    private var part: IELTSPaperLesson.SpeakingPart? { lesson.speakingPart }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header

                switch part {
                case .one: partOne
                case .two: partTwo
                case .three: partThree
                case nil: unknownPart
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.examPaper.ignoresSafeArea())
        .navigationTitle("Speaking")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRubric) {
            SpeakingRubricSheet(lesson: lesson) { showRubric = false }
        }
        .onAppear { hasAppeared = true }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(lesson.title)
                .font(.examDisplay(24))
                .foregroundStyle(Color.examInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.xs) {
                if let band = lesson.band {
                    LevelPill(text: "Target \(band)")
                        .accessibilityLabel("Target band of this material, \(band)")
                }
                if let part {
                    LevelPill(text: "Part \(part.rawValue)")
                }
                LevelPill(text: "\(lesson.targetMinutes) min")
            }
            if !lesson.prompt.isEmpty {
                Text(lesson.prompt.split(separator: "\n\n").first.map(String.init) ?? "")
                    .font(.examBody(13))
                    .foregroundStyle(Color.examInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .examReveal(hasAppeared)
    }

    // MARK: Part 1

    private var partOne: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            let questions = lesson.speakingQuestions
            if questions.isEmpty {
                Text("No question list shipped with this lesson.")
                    .font(.examBody(13))
                    .foregroundStyle(Color.examInkSoft)
            } else {
                SectionHeader(title: "The examiner's questions", subtitle: "Answer in two or three sentences, then stop")
                ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                    RapidQuestionRow(
                        number: index + 1,
                        question: question,
                        onFinish: registerTime
                    )
                }
            }
            rubricCard
        }
    }

    // MARK: Part 2

    @ViewBuilder
    private var partTwo: some View {
        let card = lesson.cueCard
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let card {
                CueCardView(topic: card.topic, bullets: card.bullets, scale: 1)
                    .examReveal(hasAppeared, delay: 0.05)
            }

            if let followUp = lesson.followUpQuestion {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Follow-up").examFieldLabel()
                    Text(followUp)
                        .font(.examBody(15))
                        .foregroundStyle(Color.examInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .examPage()
            }

            LongTurnControls(recorder: recorder, onFinish: registerTime)

            modelAnswerCard

            rubricCard
        }
    }

    // MARK: Part 3

    private var partThree: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            let questions = lesson.speakingQuestions
            if questions.isEmpty {
                Text("No discussion questions shipped with this lesson.")
                    .font(.examBody(13))
                    .foregroundStyle(Color.examInkSoft)
            } else {
                SectionHeader(title: "Discussion", subtitle: "One shared timer, four to five minutes")

                SharedTimerBar(
                    timer: sharedTimer,
                    caption: "Discussion time",
                    speaks: true,
                    onReset: { sharedTimer?.reset() }
                )
                .frame(height: 44)
                .padding(.horizontal, Spacing.sm)

                ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                    DiscussionRow(number: index + 1, question: question)
                }
            }
            rubricCard
        }
        .onAppear { prepareSharedTimer() }
    }

    /// One timer for the whole part, not one per question.
    @State private var sharedTimer: ExamTimer?

    private func prepareSharedTimer() {
        guard sharedTimer == nil else { return }
        sharedTimer = ExamTimer(seconds: 5 * 60, label: "Discussion time")
    }

    private var unknownPart: some View {
        EmptyStateView(
            symbol: "questionmark.circle",
            title: "Part not recognised",
            message: "This lesson's title does not say which speaking part it covers, so there is nothing to set up. The coaching notes below still apply.",
            actionTitle: nil,
            action: nil
        )
    }

    // MARK: Shared blocks

    private var modelAnswerCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                withAnimation(ExamMotion.tick) { showModelAnswer.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Model answer")
                            .font(.examDisplay(18))
                            .foregroundStyle(Color.examInk)
                        Text("Hidden by default — read yours back first")
                            .font(.examBody(11))
                            .foregroundStyle(Color.examInkSoft)
                    }
                    Spacer()
                    Image(systemName: showModelAnswer ? "chevron.up" : "chevron.down")
                        .font(.examBody(12, weight: .bold))
                        .foregroundStyle(Color.examInkSoft)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(showModelAnswer ? "Hides the model answers" : "Reveals the model answers for this lesson")

            if showModelAnswer {
                if lesson.modelAnswers.isEmpty {
                    Text("This lesson ships no model answer audio.")
                        .font(.examBody(13))
                        .foregroundStyle(Color.examInkSoft)
                } else {
                    ForEach(lesson.modelAnswers) { sample in
                        VStack(alignment: .leading, spacing: 6) {
                            if let clip = sample.audio {
                                // TODO(audio-lane): swap for the shared audio player when it lands.
                                AudioPlayerCard(clip: clip)
                                    .accessibilityLabel("Model answer")
                            }
                            Text(sample.prompt)
                                .font(.examBody(13, weight: .medium))
                                .foregroundStyle(Color.examInk)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(sample.explanation)
                                .font(.examBody(12))
                                .foregroundStyle(Color.examInkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(Spacing.sm)
                        .background(Color.examPaperSunk, in: .rect(cornerRadius: Radius.chip))
                        .transition(.opacity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .examPage()
    }

    private var rubricCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(
                title: "The four criteria",
                subtitle: "What is being scored on your speech"
            )
            Text("No recording is kept, no script is detected, and nothing here produces a band. This is the rubric to self-assess against.")
                .font(.examBody(12))
                .foregroundStyle(Color.examInkSoft)
                .fixedSize(horizontal: false, vertical: true)

            SecondaryButton(title: "Open the rubric and the drills", symbol: "list.bullet.rectangle") {
                showRubric = true
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .examPage()
    }

    /// Log the time actually spent talking. Short takes round to zero minutes, which
    /// is honest: the store counts whole minutes.
    private func registerTime(seconds: Int) {
        appState.store.registerStudy(minutes: seconds / 60, xp: 0, kind: .ielts)
    }
}

// MARK: - Recording bar

/// Record, stop, play back, re-record, discard. Elapsed time in mono so it does not
/// reflow as the digits change.
struct RecordingBar: View {
    let recorder: RecordingService
    /// Called with the take's length the moment the learner stops recording.
    var onFinish: (Int) -> Void = { _ in }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Button {
                    recorder.toggleRecording()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: buttonSymbol)
                        Text(buttonTitle)
                    }
                }
                // Styled inline rather than via PrimaryButton: the title and symbol are
                // dynamic and the colour turns with the state.
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 10)
                .background(recorder.state == .recording ? Color.examWrong : Color.examRed, in: .rect(cornerRadius: Radius.chip))
                .foregroundStyle(.white)
                .accessibilityLabel(buttonTitle)
                .accessibilityHint(buttonHint)
                .disabled(recorder.state == .requestingPermission)

                if recorder.state == .recording {
                    Text(timeString(recorder.elapsed))
                        .font(.examMono(15, weight: .semibold))
                        .foregroundStyle(Color.examWrong)
                        .accessibilityLabel("\(recorder.elapsed) seconds elapsed")
                } else if recorder.state == .recorded {
                    Text("Take ready")
                        .font(.examMono(13))
                        .foregroundStyle(Color.examInkSoft)
                }

                Spacer()

                if recorder.canPlay {
                    Button { recorder.togglePlayback() } label: {
                        Image(systemName: recorder.state == .playing ? "stop.fill" : "play.fill")
                            .font(.examBody(14, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .background(Color.examPaperSunk, in: .circle)
                    }
                    .foregroundStyle(Color.examInk)
                    .accessibilityLabel(recorder.state == .playing ? "Stop playback" : "Play back your take")
                }

                if recorder.state == .recorded || recorder.state == .playing {
                    Button { recorder.discard() } label: {
                        Image(systemName: "trash")
                            .font(.examBody(13, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .background(Color.examPaperSunk, in: .circle)
                    }
                    .foregroundStyle(Color.examInkSoft)
                    .accessibilityLabel("Delete this recording")
                    .accessibilityHint("Removes the take from this device")
                }
            }

            WaveformView(levels: recorder.waveform)
                .frame(height: 26)
                .opacity(recorder.state == .recording || recorder.state == .playing ? 1 : 0.25)
                .animation(ExamMotion.tick, value: recorder.waveform.count)

            if recorder.state == .denied {
                PermissionDeniedRow(settingsURL: recorder.settingsURL)
            }
        }
        .padding(Spacing.sm)
        .background(Color.examPaperSunk, in: .rect(cornerRadius: Radius.card))
        .accessibilityElement(children: .contain)
        // A take is over the instant the learner stops, so that is when the seconds
        // are worth banking.
        .onChange(of: recorder.state) { _, state in
            if state == .recorded { onFinish(recorder.elapsed) }
        }
    }

    private var buttonTitle: String {
        switch recorder.state {
        case .recording: return "Stop"
        case .requestingPermission: return "Asking…"
        default: return "Record"
        }
    }

    private var buttonSymbol: String {
        switch recorder.state {
        case .recording: return "stop.fill"
        case .requestingPermission: return "ellipsis"
        default: return "mic.fill"
        }
    }

    private var buttonHint: String {
        recorder.state == .recording
            ? "Stops the recording"
            : "Asks for microphone access the first time, then starts recording"
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// A refusal is never a dead end: it says what is blocked and offers the Settings link.
private struct PermissionDeniedRow: View {
    let settingsURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ErrorBanner(
                message: "Microphone access is off, so recording is unavailable. Everything else on this screen still works: you can read the questions, run the timers and work through the rubric.",
                retry: nil
            )
            if let settingsURL {
                SecondaryButton(title: "Open Settings", symbol: "gear") {
                    UIApplication.shared.open(settingsURL)
                }
                .accessibilityHint("Opens this app's settings so you can turn the microphone on")
            }
        }
        .padding(.top, 2)
    }
}

/// Recent loudness as a small bar row. Decorative for the ear, informative for the eye.
private struct WaveformView: View {
    let levels: [Double]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width / CGFloat(max(bars, 1))
            HStack(alignment: .center, spacing: 1.5) {
                ForEach(0..<max(levels.count, 8), id: \.self) { index in
                    let level = index < levels.count ? levels[index] : 0
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.examRed.opacity(0.75))
                        .frame(width: max(width - 1.5, 1), height: max(3, proxy.size.height * level))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Part 1

/// One question, its own five-second preparation window, and its own recorder.
///
/// Each row owns its recorder rather than sharing the screen's: ten identical
/// record buttons bound to one microphone state would show the same take ten times.
private struct RapidQuestionRow: View {
    let number: Int
    let question: String
    /// Seconds spent on a take, handed up so the screen can log study time.
    let onFinish: (Int) -> Void

    @State private var recorder = RecordingService()
    @State private var timer = ExamTimer(seconds: 5, label: "Think time")
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Text("\(number)")
                    .font(.examMono(13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.examRed, in: .circle)
                    .accessibilityHidden(true)
                Text(question)
                    .font(.examBody(16))
                    .foregroundStyle(Color.examInk)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    withAnimation(ExamMotion.tick) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.examBody(11, weight: .bold))
                        .foregroundStyle(Color.examInkSoft)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel(isExpanded ? "Hide question \(number)" : "Show question \(number)")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Question \(number). \(question)")

            if isExpanded {
                SharedTimerBar(
                    timer: timer,
                    caption: "Think",
                    speaks: true,
                    onReset: { timer.reset() }
                )
                .frame(height: 40)
                .padding(.horizontal, Spacing.xs)

                RecordingBar(recorder: recorder, onFinish: onFinish)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .examPage(padding: Spacing.sm)
    }
}

// MARK: - Part 2

/// The cue card, read at a glance: topic on top, three bullets under it, no clutter.
private struct CueCardView: View {
    let topic: String
    let bullets: [String]
    let scale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Cue card")
                .examFieldLabel()

            Text(topic)
                .font(.examDisplay(22 * scale))
                .foregroundStyle(Color.examInk)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(Color.examRed)
                .frame(height: 2)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(Color.examRed)
                            .padding(.top, 7)
                        Text(bullet)
                            .font(.examBody(17 * scale, weight: .medium))
                            .foregroundStyle(Color.examInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text("One minute to prepare. Then one to two minutes of talking. Notes are fine; a script is not.")
                .font(.examBody(11))
                .foregroundStyle(Color.examInkSoft)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .examPage()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cue card. \(topic). You should say: \(bullets.joined(separator: ". "))")
    }
}

/// One minute of silent preparation, then the long turn. The phases are explicit
/// because mixing them up is the most common way to waste the long turn.
private struct LongTurnControls: View {
    let recorder: RecordingService
    let onFinish: (Int) -> Void

    private enum Stage: Int { case prepare, speak, done }

    @State private var stage: Stage = .prepare
    @State private var prepareTimer = ExamTimer(seconds: 60, label: "Preparation time")
    @State private var speakTimer = ExamTimer(seconds: 120, label: "Speaking time")

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "The long turn", subtitle: "1 minute notes, then 1–2 minutes talking")

            stagePicker

            switch stage {
            case .prepare:
                SharedTimerBar(timer: prepareTimer, caption: "Prepare", speaks: true, onReset: { prepareTimer.reset() })
                    .frame(height: 46)
                Text("Note four headings, one per bullet. Reading a full paragraph in this minute is why candidates start talking late.")
                    .font(.examBody(12))
                    .foregroundStyle(Color.examInkSoft)
                    .fixedSize(horizontal: false, vertical: true)

            case .speak:
                SharedTimerBar(timer: speakTimer, caption: "Talk", speaks: true, onReset: { speakTimer.reset() })
                    .frame(height: 46)
                Text("\(speakTimer.remaining) seconds left. Aim past 90 seconds rather than for the full two minutes.")
                    .font(.examBody(12))
                    .foregroundStyle(speakTimer.isUrgent ? Color.examWrong : Color.examInkSoft)
                    .accessibilityLabel("\(speakTimer.remaining) seconds of speaking time remaining")

            case .done:
                Text("Time is up. Play it back before you decide whether it worked.")
                    .font(.examBody(13, weight: .medium))
                    .foregroundStyle(Color.examInk)
            }

            RecordingBar(recorder: recorder, onFinish: onFinish)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .examPage()
    }

    private var stagePicker: some View {
        HStack(spacing: 0) {
            ForEach([Stage.prepare, .speak, .done], id: \.rawValue) { candidate in
                Button {
                    withAnimation(ExamMotion.tick) { move(to: candidate) }
                } label: {
                    Text(title(for: candidate))
                        .font(.examBody(12, weight: .semibold))
                        .foregroundStyle(candidate == stage ? .white : Color.examInkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(candidate == stage ? Color.examRed : .clear)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(candidate == stage ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint("Switches the long turn to \(title(for: candidate).lowercased())")
            }
        }
        .background(Color.examPaperSunk, in: .rect(cornerRadius: Radius.chip))
        .clipShape(.rect(cornerRadius: Radius.chip))
    }

    private func title(for stage: Stage) -> String {
        switch stage {
        case .prepare: return "Prepare"
        case .speak: return "Talk"
        case .done: return "Done"
        }
    }

    private func move(to next: Stage) {
        guard next != stage else { return }
        stage = next
        Haptics.selection()
        switch next {
        case .prepare:
            prepareTimer.reset()
            prepareTimer.start()
            speakTimer.pause()
        case .speak:
            prepareTimer.pause()
            speakTimer.reset()
            speakTimer.start()
        case .done:
            prepareTimer.pause()
            speakTimer.pause()
            recorder.stopRecording()
            onFinish(speakTimer.total - speakTimer.remaining)
        }
    }
}

// MARK: - Part 3

private struct DiscussionRow: View {
    let number: Int
    let question: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text("\(number)")
                .font(.examMono(13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.examTeal, in: .circle)
                .accessibilityHidden(true)
            Text(question)
                .font(.examBody(16))
                .foregroundStyle(Color.examInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(Color.examPaperSunk, in: .rect(cornerRadius: Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Discussion question \(number). \(question)")
    }
}

// MARK: - Shared timer bar

/// The one timer control used by all three parts. Visible, pausable, and readable
/// aloud: the time remaining is a value, not a string of pixels.
struct SharedTimerBar: View {
    /// Optional because Part 3's shared timer is built on appear.
    let timer: ExamTimer?
    let caption: String
    /// When false, only the display is shown — used where the surrounding screen owns
    /// the play control (Part 3).
    var speaks: Bool = true
    var onReset: () -> Void = {}

    var body: some View {
        if let timer {
            content(for: timer)
        } else {
            Color.examPaperSunk.frame(height: 40).accessibilityHidden(true)
        }
    }

    private func content(for timer: ExamTimer) -> some View {
        HStack(spacing: Spacing.sm) {
            if speaks {
                Button {
                    timer.toggle()
                } label: {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.examBody(12, weight: .bold))
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .foregroundStyle(Color.examInk)
                .accessibilityLabel(timer.isRunning ? "Pause the \(caption.lowercased()) timer" : "Start the \(caption.lowercased()) timer")
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(timer.display)
                    .font(.examMono(20, weight: .semibold))
                    .foregroundStyle(timer.isUrgent ? Color.examWrong : Color.examInk)
                    .contentTransition(.numericText())
                    .animation(ExamMotion.tick, value: timer.remaining)
                Text(caption)
                    .font(.examBody(10, weight: .medium))
                    .foregroundStyle(Color.examInkSoft)
            }

            Spacer(minLength: 0)

            ProgressRing(
                progress: timer.fraction,
                lineWidth: 3,
                tint: timer.isUrgent ? Color.examWrong : Color.examRed,
                label: "\(timer.remaining)"
            )
            .frame(width: 30, height: 30)

            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.examBody(12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(.rect)
            }
            .foregroundStyle(Color.examInkSoft)
            .accessibilityLabel("Reset the \(caption.lowercased()) timer")
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(Color.examPaperSunk, in: .rect(cornerRadius: Radius.chip))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(timer.spokenLabel)
        .accessibilityValue(timer.didFinish ? "Finished" : (timer.isRunning ? "Running" : "Paused"))
    }
}

// MARK: - Rubric and drills

/// The lesson's `review` bullets as a self-assessment sheet, plus the exercise items
/// shipped with the lesson so the learner can work through the language afterwards.
private struct SpeakingRubricSheet: View {
    let lesson: IELTSPaperLesson
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showRubric = true
    @State private var showDrills = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Nobody is listening to this recording except you. The four criteria are what an examiner scores, and this app does not score any of them.")
                        .font(.examBody(13))
                        .foregroundStyle(Color.examInkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    criteriaCard

                    DisclosureGroup(isExpanded: $showRubric) {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            ForEach(Array(lesson.review.enumerated()), id: \.offset) { index, bullet in
                                HStack(alignment: .top, spacing: Spacing.sm) {
                                    Text("\(index + 1)")
                                        .font(.examMono(11, weight: .bold))
                                        .foregroundStyle(Color.examRed)
                                        .frame(width: 16, alignment: .leading)
                                        .padding(.top, 2)
                                    Text(bullet)
                                        .font(.examBody(14))
                                        .foregroundStyle(Color.examInk)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.top, Spacing.sm)
                    } label: {
                        Text("Notes for this lesson")
                            .font(.examDisplay(18))
                            .foregroundStyle(Color.examInk)
                    }
                    .tint(Color.examRed)

                    DisclosureGroup(isExpanded: $showDrills) {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            ForEach(lesson.items) { item in
                                // TODO(exercise-lane): confirm the ExerciseView signature for drills.
                                ExerciseView(exercise: item, topicID: "ielts", onComplete: { _ in })
                            }
                        }
                        .padding(.top, Spacing.sm)
                    } label: {
                        Text("Language drills from this lesson")
                            .font(.examDisplay(18))
                            .foregroundStyle(Color.examInk)
                    }
                    .tint(Color.examRed)
                }
                .padding(Spacing.md)
            }
            .background(Color.examPaper.ignoresSafeArea())
            .navigationTitle("Self-assessment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss(); onClose() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var criteriaCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Self.criteria, id: \.self) { criterion in
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "circle")
                        .font(.system(size: 5))
                        .foregroundStyle(Color.examRed)
                        .padding(.top, 7)
                    Text(criterion)
                        .font(.examBody(14, weight: .medium))
                        .foregroundStyle(Color.examInk)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .examPage(padding: Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The four criteria. \(Self.criteria.joined(separator: ". "))")
    }

    private static let criteria = [
        "Fluency and coherence",
        "Lexical resource",
        "Grammatical range and accuracy",
        "Pronunciation",
    ]
}