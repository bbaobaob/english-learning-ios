import SwiftUI
import EnglishCore

/// The lesson player: renders `lesson.steps` in order and writes progress as the
/// learner moves through them.
///
/// The completion rule is deliberate: opening a lesson completes nothing. The
/// lesson is only finished from the `summary` step, and only when every earlier
/// step has been visited. `visited` is derived from the persisted
/// `currentStepIndex`, so it survives a relaunch — the rail after a restart shows
/// exactly the steps the learner had actually reached.
struct LessonView: View {

    let topicID: String
    let lessonID: String

    @Environment(AppState.self) private var app

    /// Index of the step on screen; seeded from the store, then owned here.
    @State private var index: Int = 0
    /// True once the resume position has been read from the store.
    @State private var didRestore: Bool = false
    /// Highest step index the learner has reached; marks earlier steps visited.
    @State private var reached: Int = 0
    /// Set when a session step has been finished, so its own Continue shows.
    @State private var finishedSessionSteps: Set<String> = []
    /// Score shown by the quiz step's result screen.
    @State private var quizResult: QuizResult?
    /// Whether the finish button has already banked the XP.
    @State private var didComplete: Bool = false
    /// Message shown on the completion screen.
    @State private var completionNote: String?

    // MARK: - Content

    private var topic: Topic? { app.library.topic(topicID) }
    private var lesson: Lesson? { app.library.lesson(lessonID, in: topicID) }

    private var steps: [LessonStep] { lesson?.steps ?? [] }

    private var currentStep: LessonStep? {
        guard steps.indices.contains(index) else { return nil }
        return steps[index]
    }

    private var progressRow: LessonProgress? { app.store.lessonProgress()[lessonID] }

    /// Steps up to and including `reached` count as visited.
    private var visitedCount: Int {
        min(reached + 1, steps.count)
    }

    /// Whether every step before the summary has been visited. The summary's
    /// finish button stays disabled until this is true.
    private var hasVisitedEarlierSteps: Bool {
        steps.enumerated().allSatisfy { offset, step in
            step.type == .summary || offset <= reached
        }
    }

    private var isSummaryStep: Bool {
        currentStep?.type == .summary
    }

    private var lessonXP: Int { lesson?.xp ?? 0 }

    // MARK: - Body

    var body: some View {
        Group {
            if let lesson, let step = currentStep {
                VStack(spacing: 0) {
                    StepRail(
                        steps: steps,
                        currentIndex: index,
                        reached: reached,
                        onSelect: go(to:markingVisited:)
                    )
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.sm)
                    .floatingGlass()

                    content(for: step, lesson: lesson)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if case .summary = step {
                        summaryFooter(lesson: lesson)
                    } else if StepMeta.needsSession(step.type) {
                        sessionFooter(step: step)
                    } else {
                        stepFooter(step: step)
                    }
                }
                .background(Color.brand.opacity(0.03).ignoresSafeArea())
                .navigationTitle(lesson.title)
                .navigationBarTitleDisplayMode(.inline)
                .task { restoreOnce() }
            } else {
                EmptyStateView(
                    symbol: "questionmark.folder",
                    title: "Lesson unavailable",
                    message: "This lesson is not in the content bundle that shipped with the app.",
                    actionTitle: "Back",
                    action: { app.navigationPath.removeLast() }
                )
            }
        }
    }

    // MARK: - Resume

    /// Reads the resume position exactly once. The store is the source of truth,
    /// so a relaunch lands on the step the learner left, not at the start.
    private func restoreOnce() {
        guard !didRestore, let lesson else { return }
        didRestore = true
        let row = progressRow
        let resumeIndex = min(max(row?.currentStepIndex ?? 0, 0), max(lesson.steps.count - 1, 0))
        index = resumeIndex
        reached = resumeIndex
        didComplete = row?.completed == true
    }

    /// Moves to `target`, persisting the new position.
    ///
    /// - Parameter markingVisited: false only when jumping backwards through the
    ///   rail, where visiting an earlier step must not reset how far the learner
    ///   has got.
    private func go(to target: Int, markingVisited: Bool = true) {
        guard !steps.isEmpty else { return }
        let clamped = min(max(target, 0), steps.count - 1)
        index = clamped
        if markingVisited {
            reached = max(reached, clamped)
        }
        persist(stepIndex: clamped)
        Haptics.selection()
    }

    /// Writes the current position so the learner can resume here later.
    private func persist(stepIndex: Int) {
        guard steps.indices.contains(stepIndex) else { return }
        // A finished lesson keeps its completed flag; re-walking the steps must
        // not silently un-complete it.
        if didComplete { return }
        app.store.updateLessonProgress(
            lessonID: lessonID,
            topicID: topicID,
            stepIndex: stepIndex,
            lastStepID: steps[stepIndex].id
        )
    }

    // MARK: - Footers

    /// The single Continue action for a read step. This is what marks the step
    /// visited — the rail advances only from here.
    private func stepFooter(step: LessonStep) -> some View {
        HStack(spacing: Spacing.md) {
            if index > 0 {
                Button {
                    go(to: index - 1, markingVisited: false)
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
            }

            Button {
                if index == steps.count - 1 {
                    finishLesson()
                } else {
                    go(to: index + 1)
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Text(StepMeta.continueTitle(step.type))
                    if index < steps.count - 1 {
                        Image(systemName: "chevron.right")
                    }
                }
                .font(.headline)
                .frame(maxWidth: 260)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .floatingGlass()
    }

    /// Exercise steps keep their Continue hidden until the session is finished,
    /// so a step cannot be counted as visited without doing the work.
    private func sessionFooter(step: LessonStep) -> some View {
        HStack(spacing: Spacing.md) {
            if index > 0 {
                Button {
                    go(to: index - 1, markingVisited: false)
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
            }

            if finishedSessionSteps.contains(step.id) {
                Button {
                    go(to: index + 1)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Text("Continue")
                        Image(systemName: "chevron.right")
                    }
                    .font(.headline)
                    .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Text("Finish the set to move on.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 260)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .floatingGlass()
    }

    private func summaryFooter(lesson: Lesson) -> some View {
        VStack(spacing: Spacing.sm) {
            if didComplete {
                Label("Lesson complete — \(lessonXP) XP banked", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.success)
                if let note = completionNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                nextButtons(lesson: lesson)
            } else {
                Button {
                    finishLesson()
                } label: {
                    Text(hasVisitedEarlierSteps ? "Finish lesson" : "Visit every step first")
                        .font(.headline)
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!hasVisitedEarlierSteps)
                .accessibilityHint(
                    hasVisitedEarlierSteps
                        ? "Marks this lesson complete and banks its XP"
                        : "Every earlier step must be visited before the lesson can be finished"
                )

                if !hasVisitedEarlierSteps {
                    Text("Step \(reached + 1) of \(steps.count) reached.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .floatingGlass()
    }

    @ViewBuilder
    private func nextButtons(lesson: Lesson) -> some View {
        let nextLessonID = nextLessonID(in: lesson)
        HStack(spacing: Spacing.md) {
            Button {
                go(to: 0, markingVisited: false)
            } label: {
                Label("Review from the start", systemImage: "arrow.counterclockwise")
                    .font(.headline)
            }
            .buttonStyle(.bordered)

            if let nextLessonID {
                NavigationLink(value: LearnRoute.lesson(topicID: topicID, lessonID: nextLessonID)) {
                    Label("Next lesson", systemImage: "arrow.right")
                        .font(.headline)
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    /// Prefers the summary's own `nextLessonID`, then the content order.
    private func nextLessonID(in lesson: Lesson) -> String? {
        if case .summary(let summaryStep) = lesson.steps.last, let next = summaryStep.nextLessonID,
           app.library.lesson(next, in: topicID) != nil {
            return next
        }
        guard let current = topic, let at = current.lessons.firstIndex(where: { $0.id == lesson.id }),
              current.lessons.indices.contains(at + 1) else {
            return nil
        }
        return current.lessons[at + 1].id
    }

    /// Banks the XP once. Guards against a double tap.
    private func finishLesson() {
        guard !didComplete else { return }
        guard hasVisitedEarlierSteps else {
            Haptics.warning()
            return
        }
        reached = max(reached, steps.count - 1)
        didComplete = true
        app.store.completeLesson(lessonID, topicID: topicID, xp: lessonXP)
        Haptics.success()
        let hasNext = lesson.map { nextLessonID(in: $0) != nil } ?? false
        completionNote = hasNext ? nil : "This was the last lesson in the topic."
    }

    // MARK: - Step content

    @ViewBuilder
    private func content(for step: LessonStep, lesson: Lesson) -> some View {
        switch step {
        case .theory(let theory):
            TheoryStepView(step: theory)
        case .examples(let examples):
            ExamplesStepView(examples: examples.examples)
        case .audio(let audio):
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    SectionHeader(title: audio.title ?? "Listen", subtitle: nil)
                    // TODO(design-system-lane): replace with the shared App/Audio
                    // player view — replay, loop, shuffle, speed and slow. Its
                    // init is not in the contract yet; this lane ships the
                    // controls it can drive through `AppState.audio`.
                    AudioStepPlayer(clip: audio.audio, title: audio.title)
                }
                .padding(Spacing.md)
            }
        case .video(let video):
            VideoLessonView(
                video: video.video,
                bookmark: app.store.bookmark(video.video.id),
                position: 0
            )
            .padding(.horizontal, Spacing.md)
        case .exercises(let step):
            sessionHost(items: step.exercises.map { .exercise($0) }, stepID: step.id)
        case .listening(let step):
            sessionHost(items: step.exercises.map { .exercise($0) }, stepID: step.id)
        case .quiz(let step):
            quizHost(step: step)
        case .dictation(let step):
            sessionHost(items: step.items.map { .dictation($0) }, stepID: step.id)
        case .practice(let step):
            sessionHost(items: practiceItems(for: step), stepID: step.id)
        case .summary(let step):
            SummaryStepView(step: step, xp: lessonXP)
        }
    }

    /// Resolves a practice step's exercise ids through the content library.
    private func practiceItems(for step: PracticeStep) -> [SessionItem] {
        step.exerciseIDs.compactMap { id in
            app.library.exercise(id).map { SessionItem.exercise($0) }
        }
    }

    /// Hosts an `ExerciseView` for the step's items and records that the step
    /// has been worked through once the session finishes.
    @ViewBuilder
    private func sessionHost(items: [SessionItem], stepID: String) -> some View {
        if items.isEmpty {
            EmptyStateView(
                symbol: "tray",
                title: "Nothing to practise yet",
                message: "This step references content that is not in the current bundle.",
                actionTitle: nil,
                action: nil
            )
        } else {
            // TODO(design-system-lane): confirm ExerciseView's init labels; the
            // contract names the view but not its signature.
            ExerciseView(
                items: items,
                topicID: topicID,
                lessonID: lessonID,
                stepID: stepID,
                onFinish: { _ in
                    finishedSessionSteps.insert(stepID)
                    reached = max(reached, index)
                    persist(stepIndex: index)
                }
            )
        }
    }

    /// A quiz renders the shared exercise flow, then a score screen against the
    /// step's own pass mark, with the questions that were wrong.
    @ViewBuilder
    private func quizHost(step: QuizStep) -> some View {
        let questions = step.questions.map { SessionItem.exercise($0) }
        if questions.isEmpty {
            EmptyStateView(
                symbol: "list.number",
                title: "No questions in this quiz",
                message: "This quiz has no question content in the current bundle.",
                actionTitle: nil,
                action: nil
            )
        } else if let result = quizResult {
            QuizScoreView(
                result: result,
                passPercent: step.passPercent,
                questions: step.questions,
                explanations: Dictionary(
                    uniqueKeysWithValues: step.questions.map { ($0.id, $0.explanation) }
                ),
                onRetry: {
                    quizResult = nil
                    finishedSessionSteps.remove(step.id)
                },
                onContinue: { go(to: index + 1) }
            )
        } else {
            // TODO(design-system-lane): confirm ExerciseView's init labels.
            ExerciseView(
                items: questions,
                topicID: topicID,
                lessonID: lessonID,
                stepID: step.id,
                onFinish: { outcome in
                    let result = QuizResult(outcome: outcome, total: step.questions.count)
                    quizResult = result
                    if result.percent >= step.passPercent {
                        Haptics.success()
                    } else {
                        Haptics.warning()
                    }
                }
            )
        }
    }
}

// MARK: - Step rail

/// The persistent segmented rail: one segment per step, filled once visited.
struct StepRail: View {

    let steps: [LessonStep]
    let currentIndex: Int
    let reached: Int
    let onSelect: (Int) -> Void

    private var currentType: LessonStep.StepType? {
        steps.indices.contains(currentIndex) ? steps[currentIndex].type : nil
    }

    private var label: String {
        guard let currentType else { return "" }
        let number = min(currentIndex + 1, steps.count)
        return "Step \(number) of \(steps.count) · \(StepMeta.title(currentType))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                if let currentType {
                    Image(systemName: StepMeta.icon(currentType))
                        .foregroundStyle(.brand)
                        .accessibilityHidden(true)
                }
                Text(label)
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: 0)
                Text("\(visitedCount)/\(steps.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(visitedCount) of \(steps.count) steps visited")
            }

            HStack(spacing: 3) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { offset, step in
                    let visited = offset <= reached
                    Button {
                        // Only steps already reached can be jumped to; going
                        // forward always goes through the step's own action.
                        if offset <= reached { onSelect(offset) }
                    } label: {
                        ZStack {
                            Capsule()
                                .fill(visited ? Color.brand : Color.secondary.opacity(0.22))
                                .frame(height: 6)
                            if offset == currentIndex {
                                Capsule()
                                    .fill(Color.brand)
                                    .frame(height: 6)
                            }
                            if visited {
                                Capsule().fill(Color.white.opacity(0.35)).frame(height: 2)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(offset > reached)
                    .accessibilityLabel("Step \(offset + 1), \(StepMeta.title(step.type))")
                    .accessibilityValue(offset <= reached ? "Visited" : "Not visited")
                }
            }
        }
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Step views

/// A theory card: heading, body, rules with formulas and examples.
struct TheoryStepView: View {

    let step: TheoryStep
    @Environment(AppState.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if !step.heading.isEmpty {
                    Text(step.heading)
                        .font(.title2.bold())
                }

                if !step.body.isEmpty {
                    // The body carries paragraph breaks; prose reads better split.
                    ForEach(step.body.components(separatedBy: "\n\n"), id: \.self) { paragraph in
                        let text = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            Text(text)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                ForEach(step.rules) { rule in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(rule.title)
                            .font(.headline)
                        Text(rule.statement)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let formula = rule.formula, !formula.isEmpty {
                            FormulaBlock(formula: formula)
                        }

                        if !rule.examples.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                ForEach(rule.examples) { example in
                                    ExampleRow(example: example)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
            }
            .padding(Spacing.md)
        }
    }
}

/// The audio step's controls.
///
/// `speech` clips are `AVSpeechSynthesizer` audio, so play / replay / speed /
/// slow are all a rate on the same utterance. `file` and `remote` clips go to
/// the shared player service.
/// TODO(design-system-lane): replace with the App/Audio player view once its
/// init is in the contract; this drives the same clip through `AppState.audio`.
struct AudioStepPlayer: View {

    let clip: AudioClip
    let title: String?

    @Environment(AppState.self) private var app
    @State private var speedIndex: Int = 1
    @State private var isLooping: Bool = false
    @State private var hasPlayed: Bool = false

    private let speeds: [Float] = [0.5, 0.4, 0.3]

    private var speedLabel: String {
        switch speedIndex {
        case 0: "Normal"
        case 1: "Steady"
        default: "Slow"
        }
    }

    private var spokenText: String? {
        clip.kind == .speech ? clip.text : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let title {
                Text(title)
                    .font(.headline)
            }

            if let text = spokenText {
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.brand.opacity(0.08), in: .rect(cornerRadius: Radius.card))
            } else {
                Text(clip.fileName ?? clip.url?.lastPathComponent ?? "Audio clip")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Spacing.md) {
                Button {
                    play(rate: speeds[speedIndex])
                } label: {
                    Label(hasPlayed ? "Replay" : "Play", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    speedIndex = (speedIndex + 1) % speeds.count
                    Haptics.selection()
                } label: {
                    Label(speedLabel, systemImage: "gauge.with.dots.needle.33percent")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Playback speed, \(speedLabel)")
                .accessibilityHint("Changes how fast the audio is read aloud")
            }

            Toggle(isOn: $isLooping) {
                Label("Loop this clip", systemImage: "repeat")
                    .font(.subheadline)
            }
            .onChange(of: isLooping) { _, looping in
                app.audio.setLooping(looping, for: clip)
            }

            if spokenText != nil {
                Button {
                    play(rate: SpeakGate.slowRate)
                } label: {
                    Label("Play slowly", systemImage: "tortoise")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Reads the clip at a slower pace")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func play(rate: Float) {
        hasPlayed = true
        if let text = spokenText {
            SpeakGate.say(text, using: app, rate: rate)
        } else {
            app.audio.play(clip)
        }
    }
}

/// A structural formula, set monospaced and boxed so it reads as structure and
/// not as another sentence.
struct FormulaBlock: View {

    let formula: String

    var body: some View {
        Text(formula)
            .font(.system(.body, design: .monospaced).weight(.medium))
            .foregroundStyle(.brand)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(Color.brand.opacity(0.10), in: .rect(cornerRadius: Radius.chip))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.brand)
                    .frame(width: 3)
            }
            .clipShape(.rect(cornerRadius: Radius.chip))
            .accessibilityLabel("Formula, \(formula)")
    }
}

/// One bilingual example. The Vietnamese reads as a gloss under the English, and
/// tapping the English speaks it.
struct ExampleRow: View {

    let example: Example
    @Environment(AppState.self) private var app
    @State private var isSpeaking = false

    var body: some View {
        Button {
            speak()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(example.en)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                        .font(.caption)
                        .foregroundStyle(.brand)
                        .accessibilityHidden(true)
                }
                Text(example.vi)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = example.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(example.en)
        .accessibilityHint(example.vi + ". Double tap to hear it read aloud.")
    }

    private func speak() {
        SpeakGate.say(example.en, using: app)
        isSpeaking = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            isSpeaking = false
        }
    }
}

/// The lesson's closing card: takeaways and the XP on offer.
struct SummaryStepView: View {

    let step: SummaryStep
    let xp: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                SectionHeader(title: "What you learned", subtitle: nil)

                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(Array(step.takeaways.enumerated()), id: \.offset) { _, takeaway in
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.brand)
                                .accessibilityHidden(true)
                            Text(takeaway)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                HStack {
                    XPBadge(xp: xp)
                    Text("Banked when you finish.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            .padding(Spacing.md)
        }
    }
}

// MARK: - Quiz score

/// The quiz score screen: pass or fail against the step's pass mark, plus the
/// questions that were wrong and why.
struct QuizScoreView: View {

    let result: QuizResult
    let passPercent: Double
    let questions: [Exercise]
    let explanations: [String: String]
    let onRetry: () -> Void
    let onContinue: () -> Void

    private var percent: Double { result.percent }
    private var isPass: Bool { percent >= passPercent }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                ProgressRing(
                    progress: min(max(result.accuracy, 0), 1),
                    lineWidth: 12,
                    tint: isPass ? .success : .danger,
                    label: "\(Int(percent.rounded())) percent"
                )
                .padding(.top, Spacing.md)

                Text(isPass ? "Passed" : "Not yet")
                    .font(.title2.bold())
                    .foregroundStyle(isPass ? .success : .danger)

                Text("Pass mark \(Int(passPercent)) percent. \(result.correctCount) of \(questions.count) correct.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.md)

                if !result.wrongIDs.isEmpty {
                    SectionHeader(title: "Review these", subtitle: nil)
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ForEach(result.wrongIDs, id: \.self) { id in
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(prompt(for: id))
                                    .font(.subheadline.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                if let explanation = explanations[id], !explanation.isEmpty {
                                    Text(explanation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                } else {
                    EmptyStateView(
                        symbol: "hand.thumbsup",
                        title: "Nothing to review",
                        message: "Every question was right first time.",
                        actionTitle: nil,
                        action: nil
                    )
                }

                VStack(spacing: Spacing.sm) {
                    PrimaryButton(
                        title: isPass ? "Continue" : "Continue anyway",
                        symbol: "arrow.right",
                        isEnabled: true,
                        action: onContinue
                    )
                    if !isPass || !result.wrongIDs.isEmpty {
                        SecondaryButton(title: "Try the quiz again", symbol: "arrow.counterclockwise", action: onRetry)
                    }
                }
                .padding(.bottom, Spacing.lg)
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    private func prompt(for id: String) -> String {
        questions.first { $0.id == id }?.prompt ?? id
    }
}

/// A read-only snapshot of a finished session, used by the quiz score screen.
///
/// All arithmetic here is presentation: the counts and the accuracy come from
/// the session, never from a second grading pass in the view.
struct QuizResult {
    let correctCount: Int
    let accuracy: Double
    let wrongIDs: [String]

    init(outcome: SessionOutcome, total: Int) {
        self.accuracy = outcome.accuracy
        self.wrongIDs = outcome.wrongIDs
        self.correctCount = max(total - outcome.wrongIDs.count, 0)
    }

    var percent: Double { accuracy * 100 }
}
