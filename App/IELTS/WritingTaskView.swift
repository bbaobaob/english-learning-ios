import EnglishCore
import SwiftUI

/// A real writing workspace for Task 1 and Task 2.
///
/// The 40-minute clock is the real exam's. The rubric is on screen the whole time,
/// because an essay written without it is an essay written blind. Nothing here grades
/// the essay or predicts a band: the self-check is a list of things the learner can
/// look for themselves.
struct WritingTaskView: View {
    let lesson: IELTSPaperLesson

    @Environment(AppState.self) private var appState

    @State private var drafts = WritingDraftStore()
    @State private var text = ""
    @State private var timer = ExamTimer(seconds: 40 * 60, label: "Task time")
    @State private var showGuide = true
    @State private var showChecklist = false
    @State private var showHelpers = false
    @State private var checks: [SelfCheckItem] = []
    @State private var didLoad = false
    @State private var hasAppeared = false
    @State private var hasSubmitted = false
    @State private var accuracy: Double = 0
    /// `.alert` needs a settable binding; the timer's own flag is read-only.
    @State private var showTimeUpAlert = false

    private var wordCount: Int { ExamWordCount.words(in: text) }
    private var minimumWords: Int { lesson.minimumWords }

    var body: some View {
        VStack(spacing: 0) {
            timerBar
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    taskText
                    editor
                    if showGuide { structureGuide }
                    selfCheckSection
                    helperSection
                    if hasSubmitted { outcomeCard }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, 140)
            }
        }
        .background(Color.examPaper.ignoresSafeArea())
        .navigationTitle(lesson.isTask1 ? "Task 1" : "Task 2")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showChecklist) {
            SelfCheckSheet(checks: $checks, text: text) {
                showChecklist = false
                showOutcome()
            }
        }
        .onAppear(perform: load)
        .onDisappear { saveDraft() }
    }

    // MARK: Load / save

    private func load() {
        hasAppeared = true
        guard !didLoad else { return }
        didLoad = true
        text = drafts.text(for: lesson.id)
        checks = SelfCheckItem.items(for: lesson)
        // Time already spent on a previous visit comes back, but the clock never
        // runs in the background: it starts when the learner starts it.
        let spent = drafts.secondsSpent(for: lesson.id)
        if spent > 0, spent < timer.total {
            timer.adopt(elapsed: spent)
        }
    }

    private func saveDraft() {
        drafts.save(text: text, secondsSpent: timer.elapsed, for: lesson.id)
        appState.store.updateLessonProgress(
            lessonID: lesson.id,
            topicID: "ielts",
            stepIndex: text.isEmpty ? 0 : 1,
            lastStepID: "draft"
        )
    }

    /// Keystrokes land here; the disk write does not. A write per character would
    /// make the editor stutter on a long essay, and a draft that lags half a second
    /// behind the screen loses nothing.
    @State private var saveTask: Task<Void, Never>?

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await self?.saveDraft()
        }
    }

    // MARK: Timer bar

    /// Visible, quiet, pausable. Sits on a floating glass bar so it is always in the
    /// same place whether or not the keyboard is up.
    private var timerBar: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                timer.toggle()
                if timer.isRunning { Haptics.selection() }
                if !timer.isRunning { saveDraft() }
            } label: {
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.examBody(13, weight: .bold))
                    .frame(width: 34, height: 34)
                    .contentShape(.rect)
            }
            .foregroundStyle(Color.examInk)
            .accessibilityLabel(timer.isRunning ? "Pause the timer" : "Start the timer")
            .accessibilityHint("The task time is 40 minutes, as in the real test")

            Text(timer.display)
                .font(.examMono(19, weight: .semibold))
                .foregroundStyle(timer.isUrgent ? Color.examWrong : Color.examInk)
                .contentTransition(.numericText())
                .animation(ExamMotion.tick, value: timer.remaining)
                // The clock is a value, not a picture of one. VoiceOver re-reads it
                // whenever it changes because it is a live region.
                .accessibilityLabel(timer.spokenLabel)
                .accessibilityAddTraits(.updatesFrequently)

            Text("of 40:00")
                .font(.examBody(12))
                .foregroundStyle(Color.examInkSoft)

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(wordCount) words")
                    .font(.examMono(13, weight: .medium))
                    .foregroundStyle(wordCount >= minimumWords ? Color.examCorrect : Color.examInk)
                Text("min \(minimumWords)")
                    .font(.examBody(10))
                    .foregroundStyle(Color.examInkSoft)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(wordCount) words written, minimum \(minimumWords)")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .examFloatingGlass()
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xs)
        .alert("Time is up", isPresented: $showTimeUpAlert) {
            Button("Keep writing") { timer.pause() }
            Button("Stop and review") { showChecklist = true }
        } message: {
            Text("The 40 minutes for this task are gone. You can still finish your answer.")
        }
        // Fired once, when the clock reaches zero, rather than held by the binding.
        .onChange(of: timer.didFinish) { _, finished in
            if finished { showTimeUpAlert = true }
        }
        .examReveal(hasAppeared)
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
                LevelPill(text: lesson.isAcademic ? "Academic" : "General Training")
                LevelPill(text: lesson.isTask1 ? "Task 1" : "Task 2")
                LevelPill(text: "40 min")
            }
            Text("Self-authored task. Not official IELTS™ material.")
                .font(.examBody(11))
                .foregroundStyle(Color.examInkSoft.opacity(0.8))
        }
        .padding(.top, Spacing.sm)
        .examReveal(hasAppeared, delay: 0.05)
    }

    // MARK: Task text

    private var taskText: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(
                title: lesson.isTask1 ? "The task" : "The question",
                subtitle: lesson.isTask1 ? "Report the data" : "Answer the question"
            )
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(Array(taskParagraphs.enumerated()), id: \.offset) { index, paragraph in
                    TaskTextBlock(text: paragraph, style: style(for: index))
                }
            }
            if let translation = lesson.translation {
                DisclosureGroup("Tiếng Việt") {
                    Text(translation)
                        .font(.examBody(13))
                        .foregroundStyle(Color.examInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .font(.examBody(12, weight: .medium))
                .tint(Color.examInkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .examPage()
        .examReveal(hasAppeared, delay: 0.1)
    }

    private var taskParagraphs: [String] {
        lesson.prompt
            .split(separator: "\n\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// The instruction paragraph is the one that ends in the word count; the rest is
    /// the question or the data. Bullet paragraphs become lists.
    private func style(for index: Int) -> TaskTextBlock.Style {
        let text = taskParagraphs[index]
        if text.hasPrefix("•") { return .bullets }
        if text.localizedCaseInsensitiveContains("Write at least") { return .requirement }
        if index == taskParagraphs.count - 1 { return .instruction }
        return .body
    }

    // MARK: Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                SectionHeader(
                    title: "Your answer",
                    subtitle: drafts.isPersisting ? "Saved automatically" : "Not saved — storage unavailable"
                )
                Spacer()
                Button {
                    saveTask?.cancel()
                    text = ""
                    saveDraft()
                    Haptics.warning()
                } label: {
                    Image(systemName: "trash")
                        .font(.examBody(12, weight: .semibold))
                        .foregroundStyle(Color.examInkSoft)
                        .padding(6)
                }
                .accessibilityLabel("Clear your answer")
                .accessibilityHint("Deletes the draft for this task")
            }

            TextEditor(text: $text)
                .font(.examBody(16))
                .foregroundStyle(Color.examInk)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 320)
                .padding(Spacing.xs)
                .ruledPaper()
                .background(Color.examPaperSunk.opacity(0.5), in: .rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.examRule, lineWidth: 1)
                )
                .onChange(of: text) { _, _ in scheduleSave() }
                .accessibilityLabel("Your answer")
                .accessibilityHint("Write your essay here. Your draft is saved automatically")

            if !drafts.isPersisting {
                ErrorBanner(message: "This device would not open the draft store, so your answer is only in memory until you leave.", retry: nil)
            }

            HStack(spacing: Spacing.sm) {
                Text("\(ExamWordCount.sentences(in: text)) sentences")
                Text("·")
                Text(wordCount < minimumWords ? "\(minimumWords - wordCount) to go" : "Length met")
                    .foregroundStyle(wordCount < minimumWords ? Color.examRed : Color.examCorrect)
                Spacer()
                SecondaryButton(title: "Self-check", symbol: "checklist") { showChecklist = true }
            }
            .font(.examBody(12))
            .foregroundStyle(Color.examInkSoft)
        }
        .examReveal(hasAppeared, delay: 0.15)
    }

    // MARK: Structure guide

    /// The lesson's `review` strings, in front of the learner while they write.
    private var structureGuide: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                withAnimation(ExamMotion.tick) { showGuide.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Structure guide")
                            .font(.examDisplay(19))
                            .foregroundStyle(Color.examInk)
                        Text("Read this before you finish, not after")
                            .font(.examBody(11))
                            .foregroundStyle(Color.examInkSoft)
                    }
                    Spacer()
                    Image(systemName: showGuide ? "chevron.up" : "chevron.down")
                        .font(.examBody(12, weight: .bold))
                        .foregroundStyle(Color.examInkSoft)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(showGuide ? "Collapses the structure guide" : "Expands the structure guide")

            if showGuide {
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
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .examPage()
        .examReveal(hasAppeared, delay: 0.2)
    }

    // MARK: Self-check

    private var selfCheckSection: some View {
        SecondaryButton(title: "Run the self-check", symbol: "checklist") {
            showChecklist = true
        }
        .frame(maxWidth: .infinity)
        .accessibilityHint("Opens a list of things to look for before you submit")
    }

    // MARK: Helpers

    /// The language items that belong to this task, offered as optional drills.
    /// Never a gate: the submit path does not require them.
    private var helperSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                withAnimation(ExamMotion.tick) { showHelpers.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vocabulary and grammar helper")
                            .font(.examDisplay(18))
                            .foregroundStyle(Color.examInk)
                        Text("\(lesson.helperExercises.count) optional drills from this task")
                            .font(.examBody(11))
                            .foregroundStyle(Color.examInkSoft)
                    }
                    Spacer()
                    Image(systemName: showHelpers ? "chevron.up" : "chevron.down")
                        .font(.examBody(12, weight: .bold))
                        .foregroundStyle(Color.examInkSoft)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(showHelpers ? "Collapses the drills" : "Expands the drills")

            if showHelpers {
                if lesson.helperExercises.isEmpty {
                    Text("This task ships no extra drills.")
                        .font(.examBody(13))
                        .foregroundStyle(Color.examInkSoft)
                } else {
                    Text("Optional. Working through these is not part of your essay, and nothing here is graded against your writing.")
                        .font(.examBody(12))
                        .foregroundStyle(Color.examInkSoft)
                        .padding(.bottom, 2)

                    ForEach(lesson.helperExercises) { exercise in
                        ExerciseView(
                            exercise: exercise,
                            topicID: "ielts",
                            onComplete: { _ in }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .examPage()
    }

    // MARK: Outcome

    private func showOutcome() {
        timer.pause()
        saveDraft()
        checks = SelfCheckItem.evaluate(checks, text: text)
        accuracy = Double(checks.filter(\.isChecked).count) / Double(max(checks.count, 1))
        hasSubmitted = true
        appState.store.completeLesson(lesson.id, topicID: "ielts", xp: 0)
        appState.store.registerStudy(minutes: timer.elapsed / 60, xp: 0, kind: .ielts)
        Haptics.success()
    }

    private var outcomeCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "After your answer", subtitle: "Your words, and what the task wants")

            Text("You checked \(Int((accuracy * 100).rounded()))% of the self-check items yourself. That is your own assessment, not a mark.")
                .font(.examBody(12))
                .foregroundStyle(Color.examInkSoft)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.sm) {
                StatCard(
                    title: "You wrote",
                    value: "\(wordCount)",
                    caption: "words",
                    symbol: "text.word.spacing",
                    tint: .examInk
                )
                StatCard(
                    title: "Required",
                    value: "≥\(minimumWords)",
                    caption: wordCount >= minimumWords ? "met" : "short by \(minimumWords - wordCount)",
                    symbol: "target",
                    tint: wordCount >= minimumWords ? .examCorrect : .examWrong
                )
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("What this task rewards").examFieldLabel()
                ForEach(Array(lesson.review.enumerated()), id: \.offset) { index, bullet in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Text("\(index + 1)")
                            .font(.examMono(11, weight: .bold))
                            .foregroundStyle(Color.examRed)
                            .frame(width: 16, alignment: .leading)
                            .padding(.top, 2)
                        Text(bullet)
                            .font(.examBody(13))
                            .foregroundStyle(Color.examInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !comparisonMaterial.isEmpty {
                modelAnswerSection
            }

            Text("This app does not score your writing and will not tell you a band. The comparison below is a prompt to read your own answer against, not a mark.")
                .font(.examBody(12))
                .foregroundStyle(Color.examInkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .examPage()
    }

    /// The sample-answer material shipped with the lesson.
    ///
    /// Writing lessons ship their exemplars as exercise items — a model opening
    /// sentence, a corrected report — rather than as audio, so when there is no
    /// playable model the prompts themselves are the thing to read your answer against.
    private var modelAnswerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(lesson.modelAnswers.isEmpty ? "Compare against the exemplars" : "Sample-answer material").examFieldLabel()
            ForEach(comparisonMaterial) { sample in
                VStack(alignment: .leading, spacing: 6) {
                    Text(sample.prompt)
                        .font(.examBody(14, weight: .medium))
                        .foregroundStyle(Color.examInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if let clip = sample.audio {
                        AudioPlayerCard(clip: clip)
                            .accessibilityLabel("Sample answer audio")
                    }
                    DisclosureGroup("How it is marked") {
                        Text(sample.explanation)
                            .font(.examBody(13))
                            .foregroundStyle(Color.examInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .font(.examBody(12, weight: .medium))
                    .tint(Color.examRed)
                }
                .padding(Spacing.sm)
                .background(Color.examPaperSunk, in: .rect(cornerRadius: Radius.chip))
            }
        }
    }

    private var comparisonMaterial: [Exercise] {
        lesson.modelAnswers.isEmpty ? lesson.items : lesson.modelAnswers
    }
}

// MARK: - Task text block

private struct TaskTextBlock: View {
    enum Style { case body, instruction, requirement, bullets }

    let text: String
    let style: Style

    var body: some View {
        switch style {
        case .bullets:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(Color.examRed)
                        Text(line).font(.examBody(14))
                    }
                }
            }
        case .requirement:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "textformat.size")
                    .font(.examBody(12))
                    .foregroundStyle(Color.examRed)
                Text(text)
                    .font(.examBody(15, weight: .semibold))
                    .foregroundStyle(Color.examInk)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color.examRed.opacity(0.08), in: .rect(cornerRadius: Radius.chip))
        case .instruction:
            Text(text)
                .font(.examBody(15, weight: .medium))
                .foregroundStyle(Color.examInk)
        case .body:
            Text(text)
                .font(.examBody(15))
                .foregroundStyle(Color.examInk)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var bullets: [String] {
        text.split(separator: "\n").map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: " •\t"))
        }
    }
}

// MARK: - Self-check

/// Real, checkable items. No scoring, no band, no pass/fail claim — each one is a
/// thing the learner can verify in their own text.
struct SelfCheckItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    /// True when the app can actually check it from the text alone.
    let isAutomatic: Bool
    var isChecked = false
    var measured: String?

    static func items(for lesson: IELTSPaperLesson) -> [SelfCheckItem] {
        var items: [SelfCheckItem] = []

        if lesson.isTask1 {
            items.append(SelfCheckItem(
                id: "intro",
                title: "Introduction paraphrases the task and names the period",
                detail: "Do not copy the question's wording word for word.",
                isAutomatic: false
            ))
            items.append(SelfCheckItem(
                id: "overview",
                title: "Overview paragraph picks out two or three general features",
                detail: "Trends, a peak, a low point, or the sharpest contrast — not every number.",
                isAutomatic: false
            ))
            items.append(SelfCheckItem(
                id: "past",
                title: "Reported in the simple past or passive",
                detail: "rose, peaked, remained, was recorded. No present perfect, no 'nowadays'.",
                isAutomatic: false
            ))
            items.append(SelfCheckItem(
                id: "opinion",
                title: "No opinion, cause or prediction",
                detail: "Task 1 only reports what the visual shows.",
                isAutomatic: false
            ))
        } else {
            items.append(SelfCheckItem(
                id: "position",
                title: "You stated a position on the question",
                detail: "Hedging into both sides without choosing is the thing that fails Task Response.",
                isAutomatic: false
            ))
            items.append(SelfCheckItem(
                id: "subquestions",
                title: "Both sides of the prompt are addressed",
                detail: "Re-read the question and find each half of it in your answer.",
                isAutomatic: false
            ))
            items.append(SelfCheckItem(
                id: "develop",
                title: "Each body paragraph explains and gives a consequence",
                detail: "Topic sentence, reason, how it works, what follows.",
                isAutomatic: false
            ))
            items.append(SelfCheckItem(
                id: "conclusion",
                title: "The conclusion restates the position and adds a thought",
                detail: "Not a summary of what you just said, word for word.",
                isAutomatic: false
            ))
        }

        items.append(SelfCheckItem(
            id: "links",
            title: "At least two linking devices",
            detail: "however, therefore, as a result, by contrast.",
            isAutomatic: true
        ))
        items.append(SelfCheckItem(
            id: "varied",
            title: "Sentence lengths vary",
            detail: "A short one after a long one.",
            isAutomatic: true
        ))
        items.append(SelfCheckItem(
            id: "tenses",
            title: "Tenses and articles re-checked",
            detail: "Third person -s, 'an' before a vowel sound, 'the' where you mean one specific thing.",
            isAutomatic: false
        ))

        return items
    }

    /// Runs the automatic checks against the learner's text. Returns the updated list.
    static func evaluate(_ items: [SelfCheckItem], text: String) -> [SelfCheckItem] {
        let links = ExamWordCount.linkingDeviceCount(text)
        let varied = ExamWordCount.hasVariedSentenceLength(text)
        return items.map { item in
            var copy = item
            switch item.id {
            case "links":
                copy.measured = "\(links) found"
                copy.isChecked = links >= 2
            case "varied":
                copy.measured = varied ? "varied" : "even"
                copy.isChecked = varied
            default:
                break
            }
            return copy
        }
    }
}

private struct SelfCheckSheet: View {
    @Binding var checks: [SelfCheckItem]
    let text: String
    let onSubmit: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Look at your own answer before you submit it. Ticking a box does not grade anything — it is you checking.")
                        .font(.examBody(13))
                        .foregroundStyle(Color.examInkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach($checks) { $item in
                        Toggle(isOn: $item.isChecked) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.examBody(15, weight: .medium))
                                    .foregroundStyle(Color.examInk)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(item.detail)
                                    .font(.examBody(12))
                                    .foregroundStyle(Color.examInkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let measured = item.measured {
                                    Text(measured)
                                        .font(.examMono(11))
                                        .foregroundStyle(item.isChecked ? Color.examCorrect : Color.examInkSoft)
                                }
                            }
                        }
                        .tint(Color.examRed)
                        .disabled(item.isAutomatic)
                        .accessibilityHint(item.isAutomatic ? "Checked automatically from your text" : "")
                        .examPage(padding: Spacing.sm)
                    }
                }
                .padding(Spacing.md)
            }
            .background(Color.examPaper.ignoresSafeArea())
            .navigationTitle("Self-check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { onSubmit() }
                }
            }
        }
        .presentationDetents([.large])
        // The two automatic checks run against the essay the moment the sheet opens,
        // so the learner sees what the app can already confirm rather than ticking blind.
        .onAppear { checks = SelfCheckItem.evaluate(checks, text: text) }
    }
}