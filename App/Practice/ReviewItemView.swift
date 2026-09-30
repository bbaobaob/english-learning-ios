import SwiftUI
import EnglishCore

/// One review item, presented the way its source demands, and graded back into the
/// scheduler.
///
/// Three shapes, three honest grading routes:
///
/// - `.exercise` — a re-ask. `ExerciseView` grades it through a one-item `LearnSession`,
///   and the grade is read from `SessionOutcome.wrongIDs`.
/// - `.vocabulary` — a flashcard. Nobody can grade "do you remember this" on the
///   learner's behalf, so the four SM-2 buttons are the input.
/// - `.lesson` — a re-teach. Shown as a summary, then a single "got it" grade.
struct ReviewItemView: View {

    let item: ReviewItem
    let onGrade: (SpacedRepetition.Grade) -> Void

    @Environment(AppState.self) private var appState

    /// The one-item session for an exercise re-ask.
    @State private var session: LearnSession?

    var body: some View {
        Group {
            switch item.source {
            case .exercise: exerciseBody
            case .vocabulary: vocabularyBody
            case .lesson: lessonBody
            }
        }
        .background(PracticeBackdrop())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Exercise re-ask

    @ViewBuilder
    private var exerciseBody: some View {
        if let exercise = appState.library.exercise(item.refID) {
            VStack(spacing: 0) {
                headerStrip

                if let session {
                    if session.isFinished {
                        gradedResult(session)
                    } else {
                        ExerciseView(session: session)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear { startIfNeeded(exercise) }
        } else {
            missingContent
        }
    }

    private func startIfNeeded(_ exercise: Exercise) {
        guard session == nil else { return }
        session = LearnSession(
            items: [SessionItem.exercise(exercise)],
            onComplete: { _ in Haptics.success() }
        )
    }

    /// The grade the engine's outcome implies for a graded item. The engine already
    /// decided which side of the line the answer landed on; this only maps that to the
    /// scheduler's vocabulary.
    private func engineGrade(for outcome: SessionOutcome) -> SpacedRepetition.Grade {
        outcome.wrongIDs.contains(item.refID) ? .again : .good
    }

    private func gradedResult(_ session: LearnSession) -> some View {
        let outcome = session.outcome
        let grade = engineGrade(for: outcome)
        let passed = grade != .again

        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: passed ? "checkmark.circle.fill" : "arrow.clockwise.circle.fill").font(AppFont.body(.title))
                        .foregroundStyle(passed ? Color.success : Color.warning)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(passed ? "Scheduled further out" : "Back in the queue today")
                            .font(AppFont.display(22, .bold))
                        Text(passed
                            ? "A correct review moves this item one step along the interval ladder."
                            : "This item lapsed, so it returns today and the interval resets.")
                            .font(AppFont.display(14, .regular))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                schedulePreview(grade: grade)

                PrimaryButton(
                    title: "Save and continue",
                    symbol: "checkmark",
                    isEnabled: true,
                    action: { onGrade(grade) }
                )

                Spacer(minLength: 0)
            }
            .padding(Spacing.lg)
        }
    }

    // MARK: - Vocabulary flashcard

    @ViewBuilder
    private var vocabularyBody: some View {
        if let word = appState.library.vocabWord(item.refID) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(word.word)
                            .font(AppFont.display(34, .bold))
                            .accessibilityAddTraits(.isHeader)
                        if let ipa = word.ipa {
                            Text(ipa)
                                .font(AppFont.mono(15, .regular))
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: Spacing.sm) {
                            if let topic = word.topic {
                                Chip(text: topic, isSelected: false)
                            }
                            if let level = word.level {
                                LevelPill(text: level.displayName)
                            }
                            Spacer(minLength: 0)
                            SecondaryButton(
                                title: "Hear it",
                                symbol: "speaker.wave.2.fill",
                                action: {
                                    let text = word.audio?.text ?? word.word
                                    appState.speech.speak(text, rate: word.audio?.speakingRate ?? 0.45) {}
                                    Haptics.selection()
                                }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text(word.meaning)
                            .font(AppFont.display(18, .semibold))
                            .foregroundStyle(Color.brand)
                            .fixedSize(horizontal: false, vertical: true)

                        if let example = word.example {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(example)
                                    .font(AppFont.display(15, .regular))
                                if let vi = word.exampleVI {
                                    Text(vi)
                                        .font(AppFont.display(14, .regular))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !word.collocations.isEmpty {
                            Divider()
                            Text("Collocations")
                                .font(AppFont.display(13, .semibold))
                                .foregroundStyle(.secondary)
                            CollocationList(items: word.collocations)
                        }

                        if !word.synonyms.isEmpty || !word.antonyms.isEmpty {
                            Divider()
                            if !word.synonyms.isEmpty {
                                Text("Synonyms: " + word.synonyms.joined(separator: ", "))
                                    .font(AppFont.display(14, .regular))
                            }
                            if !word.antonyms.isEmpty {
                                Text("Antonyms: " + word.antonyms.joined(separator: ", "))
                                    .font(AppFont.display(14, .regular))
                            }
                        }
                    }
                    .padding(Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()

                    gradeButtons
                    Color.clear.frame(height: Spacing.xl)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
            }
        } else {
            missingContent
        }
    }

    // MARK: - Lesson re-teach

    @ViewBuilder
    private var lessonBody: some View {
        if let lesson = appState.library.lesson(item.refID) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(lesson.title)
                            .font(AppFont.display(26, .bold))
                            .accessibilityAddTraits(.isHeader)
                        Text(lesson.summary)
                            .font(AppFont.display(15, .regular))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        SecondaryButton(
                            title: "Hear the title",
                            symbol: "speaker.wave.2.fill",
                            action: {
                                appState.speech.speak(lesson.title, rate: SpeechRate.example) {}
                                Haptics.selection()
                            }
                        )
                    }
                    .padding(Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        SectionHeader(
                            title: "Still there?",
                            subtitle: "These are the points the lesson ended on",
                            actionTitle: nil,
                            action: nil
                        )
                        ForEach(Array(takeaways.enumerated()), id: \.offset) { pair in
                            HStack(alignment: .top, spacing: Spacing.sm) {
                                Text("\(pair.offset + 1)")
                                    .font(AppFont.mono(13, .bold))
                                    .foregroundStyle(Color.brand)
                                    .frame(width: 22, alignment: .trailing)
                                Text(pair.element)
                                    .font(AppFont.display(14, .regular))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()

                    gradeButtons
                    Color.clear.frame(height: Spacing.xl)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
            }
        } else {
            missingContent
        }
    }

    /// The lesson's closing `summary` step, which is where its takeaways live.
    private var takeaways: [String] {
        guard let lesson = appState.library.lesson(item.refID) else { return [] }
        for step in lesson.steps {
            if case .summary(let summary) = step { return summary.takeaways }
        }
        return []
    }

    // MARK: - Shared chrome

    private var headerStrip: some View {
        HStack(spacing: Spacing.md) {
            Text(sourceLabel)
                .font(AppFont.mono(12, .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: Spacing.xs)
            Text("ease \(PracticeFormat.ease(item.ease))")
                .font(AppFont.mono(12, .semibold))
                .foregroundStyle(Color.brand)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }

    private var title: String {
        switch item.source {
        case .exercise: "Review · Exercise"
        case .vocabulary: "Review · Word"
        case .lesson: "Review · Lesson"
        }
    }

    private var sourceLabel: String {
        item.topicID.flatMap { appState.library.topic($0)?.title } ?? "Mixed content"
    }

    private var missingContent: some View {
        EmptyStateView(
            symbol: "questionmark.folder",
            title: "Content no longer available",
            message: "This review item points at \(item.refID), which is not in the loaded course. It will keep coming back until the content returns.",
            actionTitle: nil,
            action: nil
        )
    }

    /// The four SM-2 grades, offered as buttons for the self-graded sources.
    private var gradeButtons: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(
                title: "How did that go?",
                subtitle: "Your answer moves the next review date",
                actionTitle: nil,
                action: nil
            )

            VStack(spacing: Spacing.sm) {
                ForEach(Self.gradeOptions, id: \.value) { option in
                    Button {
                        Haptics.selection()
                        onGrade(option.value)
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: option.symbol)
                                .foregroundStyle(option.tint)
                                .frame(width: 26)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.title)
                                    .font(AppFont.display(16, .semibold))
                                Text(option.caption)
                                    .font(AppFont.display(12, .regular))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: Spacing.xs)
                        }
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.title). \(option.caption)")
                }
            }
        }
    }

    /// Shows what the scheduler will do *before* the learner commits, so the system is
    /// visible rather than mysterious. The numbers come from `SpacedRepetition` itself.
    private func schedulePreview(grade: SpacedRepetition.Grade) -> some View {
        let next = SpacedRepetition().schedule(item, grade: grade)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(
                title: "What the scheduler will do",
                subtitle: "Computed by SpacedRepetition, not by this screen",
                actionTitle: nil,
                action: nil
            )
            HStack(spacing: Spacing.md) {
                StatCard(
                    title: "Next due",
                    value: next.dueDate.formatted(date: .abbreviated, time: .omitted),
                    caption: next.intervalDays == 0 ? "today" : "in \(PracticeFormat.phrase(next.intervalDays, "day", "days"))",
                    symbol: "calendar",
                    tint: .brand
                )
                StatCard(
                    title: "Ease",
                    value: PracticeFormat.ease(next.ease),
                    caption: next.repetitions == 0 ? "repetitions reset" : "\(next.repetitions) in a row",
                    symbol: "gauge.medium",
                    tint: .accuracy
                )
            }
        }
    }

    /// The four SM-2 grades, in the order the scheduler's enum declares them.
    private static let gradeOptions: [(
        value: SpacedRepetition.Grade,
        title: String,
        caption: String,
        symbol: String,
        tint: Color
    )] = [
        (.again, "Again", "Back today, interval reset", "arrow.uturn.backward", .danger),
        (.hard, "Hard", "Shorter interval, ease drops", "tortoise", .warning),
        (.good, "Good", "Normal interval", "checkmark", .brand),
        (.easy, "Easy", "Longer interval, ease rises", "arrow.up.forward", .success),
    ]
}

/// A compact chip list for collocations, synonyms, and the like.
struct CollocationList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(AppFont.mono(13, .regular))
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.brandSoft.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            }
        }
    }
}
