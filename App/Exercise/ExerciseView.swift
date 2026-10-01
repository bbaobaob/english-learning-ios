import SwiftUI
import EnglishCore

/// The session host: runs a `LearnSession` and renders each item through the
/// right view.
///
/// This is the type every screen lane instantiates. It exists so that
/// `LearnSession` is driven in exactly one place — the archive is explicit
/// that designers must not re-implement grading or flow, and the only way to
/// guarantee that is to make there be nowhere else to do it from.
///
/// The three initialisers exist because three different callers want different
/// things:
///
/// * ``init(session:)`` — the caller already has a `LearnSession` (Practice's
///   dictation, review queue, and mixed sets all drive their own so they can
///   read `outcome` and call `registerStudy` when it ends). This view borrows it.
/// * ``init(items:topicID:lessonID:stepID:onFinish:)`` — the caller wants this
///   view to own the session, which is what a lesson step and a quiz want.
/// * ``init(exercise:topicID:onComplete:)`` — one standalone exercise inside a
///   flow the lane drives itself (IELTS's inline drills).
///
/// None is a convenience wrapper over another: the first borrows a session, the
/// second creates one, and the third creates a one-item session and reports the
/// single result back instead of the totals.
struct ExerciseView: View {
    /// The session being run. Borrowed or owned; see the initialisers.
    private let session: LearnSession
    /// The topic that owns the items, for `ProgressStore.recordAttempt`.
    private let topicID: String
    /// The lesson that owns the items, when there is one.
    private let lessonID: String?
    /// Called when the session finishes, with its totals.
    private let onFinish: (SessionOutcome) -> Void

    @Environment(AudioPlayerModel.self) private var audio
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The step id the caller keyed this session by.
    ///
    /// Carried, not acted on: the item list is already scoped to the step, so
    /// nothing here needs to disambiguate. It is exposed through
    /// ``stepIdentifier`` because a lesson's progress report needs to attribute
    /// a completed step to its id, and the alternative is threading it back out
    /// through `onFinish`.
    private let stepID: String?

    /// The result for the item on screen, or `nil` before it is answered.
    ///
    /// Held locally rather than read back from the session, because
    /// `LearnSession` exposes only `results` as a flat array and matching one
    /// back to the current item would be guesswork. Re-answering replaces it
    /// here, which is the same behaviour.
    @State private var result: ExerciseResult?

    /// Called with each graded result as it lands. Only the standalone-exercise
    /// initialiser sets it; the session-driven ones report through `onFinish`
    /// instead, because a caller that owns a session wants the totals, not a
    /// stream of per-item results.
    private let onResult: ((ExerciseResult) -> Void)?

    init(session: LearnSession) {
        self.session = session
        self.topicID = session.current?.asExercise?.topicID ?? ""
        self.lessonID = session.current?.asExercise?.lessonID
        self.stepID = nil
        self.onFinish = { _ in }
        self.onResult = nil
    }

    init(
        items: [SessionItem],
        topicID: String,
        lessonID: String? = nil,
        stepID: String? = nil,
        onFinish: @escaping (SessionOutcome) -> Void
    ) {
        self.session = LearnSession(items: items)
        self.topicID = topicID
        self.lessonID = lessonID
        self.stepID = stepID
        self.onFinish = onFinish
        self.onResult = nil
    }

    /// One standalone exercise, outside any session.
    ///
    /// For the IELTS lanes' inline drills, which sit inside a paper the lane
    /// drives itself and must not be folded into the learner's session. The
    /// one-item session is created here so grading still goes through
    /// `ExerciseEngine` rather than being re-implemented; `onComplete` fires
    /// with the graded result, and the caller advances its own flow.
    init(
        exercise: Exercise,
        topicID: String,
        onComplete: @escaping (ExerciseResult) -> Void
    ) {
        self.session = LearnSession(items: [.exercise(exercise)])
        self.topicID = topicID
        self.lessonID = exercise.lessonID
        self.stepID = nil
        self.onFinish = { _ in }
        self.onResult = onComplete
    }

    var body: some View {
        Group {
            if let item = session.current {
                content(for: item)
            } else {
                // A session that has run out of items. Reached when the last
                // item is answered, because `LearnSession` sets `isFinished`
                // on that submit; showing a calm end state here means the
                // learner never sees an empty frame.
                finishedState
            }
        }
        .background(Palette.background)
        // Re-render from scratch when the item changes so no answer state
        // bleeds from one exercise into the next.
        .id(session.current?.id)
        .onChange(of: session.index) { _, _ in
            withAnimation(Motion.accessible(Motion.standard, reduceMotion: reduceMotion)) {
                result = nil
            }
        }
    }

    // MARK: - Items

    @ViewBuilder
    private func content(for item: SessionItem) -> some View {
        switch item {
        case .exercise(let exercise):
            ExerciseCard(
                exercise: exercise,
                onSubmit: { submission in submit(submission, exercise: exercise) },
                result: result,
                onContinue: advance
            )
            .padding(Spacing.lg)

        case .dictation(let dictation):
            DictationSessionCard(
                item: dictation,
                result: result,
                onSubmit: { text in
                    let graded = session.submitDictation(text)
                    record(graded, topicID: dictation.audio.id)
                },
                onContinue: advance
            )
            .padding(Spacing.lg)

        case .theory(let step):
            ReadOnlyStepCard(
                symbol: "text.book.closed",
                title: "Read",
                text: theoryText(for: step),
                onContinue: advance
            )
            .padding(Spacing.lg)

        case .video(let clip):
            // The video owns its own transport and its own bookmarking, so it
            // is presented with the controls already on it rather than as a
            // read-only step.
            VideoLessonView(
                video: clip,
                bookmark: { _ in },
                position: 0
            )
            .padding(Spacing.lg)

        case .audio(let clip):
            VStack(spacing: Spacing.lg) {
                AudioPlayerView(clip: clip)
                PrimaryButton(title: "Done", symbol: "checkmark", action: advance)
            }
            .padding(Spacing.lg)

        case .examples(let examples):
            ReadOnlyStepCard(
                symbol: "list.bullet",
                title: "Examples",
                text: examples.map(\.en).joined(separator: "\n"),
                onContinue: advance
            )
            .padding(Spacing.lg)

        case .summary(let takeaways):
            ReadOnlyStepCard(
                symbol: "checkmark.seal",
                title: "Summary",
                text: takeaways.joined(separator: "\n"),
                onContinue: advance
            )
            .padding(Spacing.lg)
        }
    }

    private var finishedState: some View {
        let outcome = session.outcome
        return VStack(spacing: Spacing.lg) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Palette.brand)
                .accessibilityHidden(true)

            Text("Session complete")
                .font(AppFont.display(.title2))
                .foregroundStyle(Palette.textPrimary)

            HStack(spacing: Spacing.xl) {
                outcomeStat(title: "Accuracy", value: Format.percent(outcome.accuracy))
                outcomeStat(title: "XP", value: "+\(outcome.xpEarned)")
            }
            .frame(maxWidth: .infinity)
            .cardStyle()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                Text(verbatim: "Session complete. Accuracy \(Format.percent(outcome.accuracy)). \(outcome.xpEarned) experience points.")
            )
        }
        .padding(Spacing.lg)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func outcomeStat(title: String, value: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(AppFont.display(.title2))
                .foregroundStyle(Palette.textPrimary)
            Text(title)
                .font(AppFont.body(.caption))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Flow

    /// Grades a submission and records it.
    private func submit(_ submission: ExerciseSubmission, exercise: Exercise) {
        let graded: ExerciseResult
        switch submission {
        case .response(let response):
            graded = session.submit(response)
        case .dictation(let text):
            // A textual exercise grades through the same engine path as
            // dictation, which is what produces the word-level diff.
            graded = session.submitDictation(text)
        }
        record(graded, topicID: exercise.topicID)
    }

    /// Stores the result for display and hands it to the store.
    ///
    private func record(_ graded: ExerciseResult, topicID: String) {
        withAnimation(Motion.accessible(Motion.standard, reduceMotion: reduceMotion)) {
            result = graded
        }
        if graded.isCorrect {
            Haptics.success()
        } else {
            Haptics.warning()
        }
        if !topicID.isEmpty {
            // Every graded attempt goes through the store, which also drives
            // the spaced-repetition schedule. Recording it here rather than in
            // each screen lane is what keeps the review queue honest.
            app.store.recordAttempt(graded, topicID: topicID, lessonID: lessonID)
        }
        onResult?(graded)
    }

    /// Moves to the next item, or finishes.
    private func advance() {
        audio.stop()
        result = nil
        let outcome = session.outcome
        if !session.next() {
            onFinish(outcome)
        }
    }

    private func theoryText(for step: LessonStep) -> String {
        guard case .theory(let theory) = step else { return "" }
        var lines = [theory.body]
        for rule in theory.rules {
            lines.append("\n\(rule.title): \(rule.statement)")
            if let formula = rule.formula {
                lines.append(formula)
            }
            for example in rule.examples {
                lines.append("\(example.en) — \(example.vi)")
            }
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

/// A dictation item rendered as a session step.
///
/// `SessionItem.dictation` is not an `Exercise`, so it needs its own card
/// rather than going through `ExerciseCard`. The loop is the same as the
/// in-exercise dictation mode — play, replay, slow replay, type, check,
/// reveal — and it reuses the same `DictationAnswerArea`, so the two cannot
/// drift apart.
private struct DictationSessionCard: View {
    let item: DictationItem
    let result: ExerciseResult?
    let onSubmit: (String) -> Void
    let onContinue: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                LevelPill(text: "Dictation")
                Text("Listen and type exactly what you hear.")
                    .font(AppFont.display(.title3))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DictationAnswerArea(text: $text, clip: item.audio, isFocused: $isFocused)

            if let result {
                ResultPanel(result: result, exercise: syntheticExercise, userText: text, onContinue: onContinue)
            } else {
                PrimaryButton(
                    title: "Check",
                    symbol: "checkmark",
                    isEnabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    action: { onSubmit(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                )
            }
        }
        .cardStyle()
        .onChange(of: item.id) { _, _ in text = "" }
    }

    /// `ResultPanel` needs an `Exercise` to resolve option labels, and a
    /// dictation result's answer is `.text`, which carries the sentence itself
    /// rather than an item id. So the labels are already correct and the
    /// exercise only has to be well formed.
    private var syntheticExercise: Exercise {
        Exercise(
            id: item.id,
            kind: .dictation,
            topicID: "",
            prompt: "",
            answer: .text([item.expectedText])
        )
    }
}

/// A step that is read rather than answered: theory, examples, a summary.
private struct ReadOnlyStepCard: View {
    let symbol: String
    let title: String
    let text: String
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Label(title, systemImage: symbol)
                .font(AppFont.body(.subheadline, weight: .semibold))
                .foregroundStyle(Palette.brand)
                .accessibilityAddTraits(.isHeader)

            Text(text)
                .font(AppFont.body(.body))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            PrimaryButton(title: "Continue", symbol: "arrow.right", action: onContinue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

extension ExerciseView {
    /// The id the caller keyed this run by, exposed for a lesson step that
    /// wants to label its own progress. `nil` when the caller supplied a
    /// session instead of an item list.
    var stepIdentifier: String? { stepID }
}
