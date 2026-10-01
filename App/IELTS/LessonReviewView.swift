import EnglishCore
import SwiftUI

/// After submission: every question, what the learner answered, what was correct,
/// why, and the lesson's `review` bullets. Dictation items show the wrong words
/// inline rather than a bare "incorrect".
struct LessonReviewScreen: View {
    let lesson: IELTSPaperLesson
    let session: LearnSession?
    /// Listening only: the transcript opens up here, because the attempt is over.
    let showTranscript: Bool

    @Environment(AppState.self) private var appState

    @State private var showBullets = true
    @State private var wrongOnly = false

    private var results: [String: ExerciseResult] {
        Dictionary(uniqueKeysWithValues: (session?.results ?? []).map { ($0.exerciseID, $0) })
    }

    private var visibleQuestions: [IELTSPaperQuestion] {
        guard wrongOnly else { return lesson.questions }
        return lesson.questions.filter { results[$0.exercise.id]?.isCorrect == false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            accuracyCard

            if lesson.hasTranscript && showTranscript {
                TranscriptPanelView(lesson: lesson, isSealed: false)
            }

            filterRow

            ForEach(visibleQuestions) { question in
                ReviewRow(
                    question: question,
                    result: results[question.exercise.id]
                )
            }

            if !lesson.review.isEmpty {
                ReviewBulletsCard(bullets: lesson.review, isExpanded: $showBullets)
            }

            doneButton
        }
    }

    // MARK: Accuracy

    /// Two numbers, always labelled apart: what the learner scored on these
    /// questions, and what band the material is pitched at.
    private var accuracyCard: some View {
        let outcome = session?.outcome
        let accuracy = outcome?.accuracy ?? 0
        let wrong = outcome?.wrongIDs.count ?? 0

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                ProgressRing(
                    progress: accuracy,
                    lineWidth: 6,
                    tint: accuracy >= 0.75 ? Color.examCorrect : Color.examWrong,
                    label: "\(Int(accuracy * 100))%"
                )
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text(ExamCopy.accuracyLabel)
                        .examFieldLabel()
                    Text("\(Int((accuracy * 100).rounded()))%")
                        .font(.examDisplay(28))
                        .foregroundStyle(Color.examInk)
                    Text(wrong == 0
                         ? "Every question correct."
                         : "\(wrong) of \(lesson.questionCount) to look at below.")
                        .font(.examBody(12))
                        .foregroundStyle(Color.examInkSoft)
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(Color.examRule)

            if let band = lesson.band {
                HStack(spacing: Spacing.sm) {
                    LevelPill(text: "Target band \(band)")
                    Text(ExamCopy.accuracyDisclaimer)
                        .font(.examBody(11))
                        .foregroundStyle(Color.examInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Target band of this material, \(band). \(ExamCopy.accuracyDisclaimer)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .examPage()
    }

    // MARK: Filter

    private var filterRow: some View {
        HStack(spacing: Spacing.sm) {
            Chip(
                text: wrongOnly ? "Showing mistakes" : "All questions",
                isSelected: wrongOnly
            ) {
                withAnimation(ExamMotion.tick) { wrongOnly.toggle() }
                Haptics.selection()
            }
            .accessibilityHint("Toggles between every question and only the ones you got wrong")
            Spacer()
            Text("\(visibleQuestions.count) shown")
                .font(.examBody(11))
                .foregroundStyle(Color.examInkSoft)
        }
    }

    // MARK: Done

    private var doneButton: some View {
        PrimaryButton(title: "Back to \(IELTSPaperLesson.skillName(lesson.skill))", symbol: "chevron.left") {
            appState.store.updateLessonProgress(
                lessonID: lesson.id,
                topicID: "ielts",
                stepIndex: lesson.questionCount,
                lastStepID: lesson.questions.last?.id
            )
        }
        .accessibilityHint("Returns to the lesson list")
    }
}

// MARK: - One question

private struct ReviewRow: View {
    let question: IELTSPaperQuestion
    let result: ExerciseResult?

    @State private var isExpanded = false

    private var status: (label: String, symbol: String, tint: Color) {
        guard let result else { return ("Not answered", "minus.circle", Color.examInkSoft) }
        if result.isCorrect { return ("Correct", "checkmark.circle.fill", Color.examCorrect) }
        if result.accuracy > 0 { return ("Partly right", "circle.lefthalf.filled", Color.examRed) }
        return ("Incorrect", "xmark.circle.fill", Color.examWrong)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Text("\(question.number)")
                    .font(.examMono(13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(status.tint, in: .circle)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(question.exercise.prompt)
                        .font(.examBody(15, weight: .medium))
                        .foregroundStyle(Color.examInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(question.exercise.kind.rawValue.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression).capitalized)
                        .font(.examBody(11))
                        .foregroundStyle(Color.examInkSoft)
                }

                Spacer(minLength: 0)

                Image(systemName: status.symbol)
                    .font(.examBody(15))
                    .foregroundStyle(status.tint)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Question \(question.number), \(status.label)")

            if isExpanded {
                answerBlock
            } else {
                Button(status.label == "Correct" ? "Show detail" : "Show what was wrong") {
                    withAnimation(ExamMotion.tick) { isExpanded = true }
                }
                .font(.examBody(13, weight: .medium))
                .foregroundStyle(Color.examRed)
                .accessibilityHint("Expands this question to show your answer, the correct answer and the explanation")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(Color.examPaper, in: .rect(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(status.tint.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var answerBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let result {
                answerRow(title: "Your answer", value: renderedUserAnswer(result), tint: result.isCorrect ? .examCorrect : .examWrong)

                if question.exercise.kind == .dictation, !result.diffs.isEmpty {
                    wordDiffView(result)
                }

                answerRow(title: "Correct answer", value: renderedCorrectAnswer(result), tint: .examCorrect)

                if !result.explanation.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Why").examFieldLabel()
                        Text(result.explanation)
                            .font(.examBody(13))
                            .foregroundStyle(Color.examInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("You did not reach this question.")
                    .font(.examBody(13))
                    .foregroundStyle(Color.examInkSoft)
                answerRow(title: "Correct answer", value: plainCorrectAnswer, tint: .examCorrect)
            }

            if !question.exercise.explanation.isEmpty, result?.explanation.isEmpty != false {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Why").examFieldLabel()
                    Text(question.exercise.explanation)
                        .font(.examBody(13))
                        .foregroundStyle(Color.examInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func answerRow(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).examFieldLabel()
            Text(value)
                .font(.examMono(13))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Dictation: the wrong words, in place, underlined rather than merely coloured —
    /// colour alone does not survive a screenshot or a colour-blind reader.
    @ViewBuilder
    private func wordDiffView(_ result: ExerciseResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Word by word").examFieldLabel()
            FlowLayout(spacing: 4) {
                ForEach(result.diffs.sorted { $0.index < $1.index }) { diff in
                    Text(displayToken(for: diff))
                        .font(.examMono(13, weight: .medium))
                        .foregroundStyle(diff.kind == .missing ? Color.examWrong : Color.examInk)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Color.examRule.opacity(0.45),
                            in: .rect(cornerRadius: 5)
                        )
                        .overlay(alignment: .bottom) {
                            if diff.kind != .missing {
                                Rectangle()
                                    .fill(diff.kind == .substituted ? Color.examWrong : Color.examInkSoft)
                                    .frame(height: 1.5)
                            }
                        }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription(for: result.diffs))
        }
    }

    private func displayToken(for diff: TokenDiff) -> String {
        switch diff.kind {
        case .missing: return diff.expected ?? ""
        case .extra: return diff.user ?? ""
        case .substituted: return "\(diff.user ?? "") → \(diff.expected ?? "")"
        }
    }

    private func accessibilityDescription(for diffs: [TokenDiff]) -> String {
        let problems = diffs.compactMap { diff -> String? in
            switch diff.kind {
            case .missing: return "missing \(diff.expected ?? "")"
            case .extra: return "extra \(diff.user ?? "")"
            case .substituted: return "\(diff.user ?? "") should be \(diff.expected ?? "")"
            }
        }
        return problems.isEmpty ? "No word-level differences." : problems.joined(separator: ", ")
    }

    // MARK: Answer rendering

    private func renderedUserAnswer(_ result: ExerciseResult) -> String {
        if !result.diffs.isEmpty {
            return displayToken(for: result.diffs.sorted { $0.index < $1.index }.first { $0.kind != .missing } ?? result.diffs[0])
        }
        return result.isCorrect ? "Correct" : "See the words below"
    }

    private func renderedCorrectAnswer(_ result: ExerciseResult) -> String {
        render(result.correctAnswer)
    }

    private var plainCorrectAnswer: String {
        render(question.exercise.answer)
    }

    private func render(_ answer: Answer) -> String {
        switch answer.values {
        case .text(let values): values.joined(separator: " / ")
        case .choice(let ids): ids.map(label(for:)).joined(separator: ", ")
        case .order(let tokens): tokens.map(label(for:)).joined(separator: " ")
        case .pairs(let map):
            map.keys.sorted().map { "\(label(for: $0)) = \(map[$0].map(label(for:)) ?? "—")" }.joined(separator: "\n")
        case .boolean(let flag): flag ? "True" : "False"
        case .none: "—"
        }
    }

    private func label(for id: String) -> String {
        question.exercise.items.first { $0.id == id }?.text ?? id
    }
}

// MARK: - The lesson's own coaching notes

struct ReviewBulletsCard: View {
    let bullets: [String]
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                withAnimation(ExamMotion.tick) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("What the examiner looks for")
                        .font(.examDisplay(18))
                        .foregroundStyle(Color.examInk)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.examBody(12, weight: .bold))
                        .foregroundStyle(Color.examInkSoft)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Collapses the notes" : "Expands the notes for this lesson")

            if isExpanded {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { index, bullet in
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Text("\(index + 1)")
                                .font(.examMono(11, weight: .bold))
                                .foregroundStyle(Color.examRed)
                                .frame(width: 18, height: 18, alignment: .leading)
                                .padding(.top, 2)
                            Text(bullet)
                                .font(.examBody(14))
                                .foregroundStyle(Color.examInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .examPage()
    }
}

// MARK: - Wrapping layout

/// Wraps chips onto new lines. Used for word-level diffs and option lists.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}