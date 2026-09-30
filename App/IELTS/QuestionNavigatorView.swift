import EnglishCore
import SwiftUI

/// A navigator grouped by the content's own `Questions 1–4` banners, so the learner
/// jumps to a question the way the paper numbers it rather than by list position.
struct QuestionNavigator: View {
    let groups: [IELTSPaperGroup]
    let currentNumber: Int?
    let answered: Set<Int>
    let onJump: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(
                title: "Questions",
                subtitle: currentNumber.map { "Question \($0) of \(totalQuestionCount)" } ?? "\(totalQuestionCount) questions"
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.label.isEmpty ? "Question" : group.label)
                                .font(.examBody(11, weight: .semibold))
                                .foregroundStyle(Color.examInkSoft)
                                .fixedSize(horizontal: false, vertical: true)

                            // Grid, because the paper prints questions in a grid.
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 40, maximum: 56), spacing: 8)],
                                spacing: 8
                            ) {
                                ForEach(group.questions) { question in
                                    NumberCell(
                                        number: question.number,
                                        isCurrent: question.number == currentNumber,
                                        isAnswered: answered.contains(question.number),
                                        action: { onJump(question.number) }
                                    )
                                }
                            }
                            .frame(width: min(CGFloat(groups.count) * 130, 280), alignment: .leading)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    private var totalQuestionCount: Int { groups.reduce(0) { $0 + $1.questions.count } }
}

private struct NumberCell: View {
    let number: Int
    let isCurrent: Bool
    let isAnswered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.selection()
            action()
        }) {
            Text("\(number)")
                .font(.examMono(13, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 40, height: 40)
                .background(background, in: .rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isCurrent ? Color.examRed : Color.examRule, lineWidth: isCurrent ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Question \(number)")
        .accessibilityValue(isAnswered ? "Answered" : "Not answered")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Jumps to question \(number)")
    }

    private var foreground: Color {
        if isCurrent { return .white }
        return isAnswered ? Color.examCorrect : Color.examInk
    }

    private var background: Color {
        if isCurrent { return .examRed }
        return isAnswered ? Color.examCorrect.opacity(0.12) : Color.examPaperSunk
    }
}

/// The transcript, sealed or open.
///
/// `isSealed` is the whole contract: while it is `true` this view renders a title and
/// nothing else — no lines, no snippet, no scrollable preview. There is no way to
/// reach the text from here.
struct TranscriptPanelView: View {
    let lesson: IELTSPaperLesson
    let isSealed: Bool

    @State private var fontScale: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Label("Transcript", systemImage: isSealed ? "lock.fill" : "text.quote")
                    .font(.examBody(15, weight: .semibold))
                    .foregroundStyle(Color.examInk)
                Spacer()
                if !isSealed {
                    sizeControl
                }
            }

            if isSealed {
                sealedBody
            } else {
                openBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .examPage()
        .accessibilityElement(children: isSealed ? .ignore : .contain)
    }

    private var sealedBody: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Hidden until you finish this attempt.")
                .font(.examBody(13))
                .foregroundStyle(Color.examInkSoft)
            Text("\(lesson.transcript.count) lines of speaker dialogue are held back.")
                .font(.examBody(12))
                .foregroundStyle(Color.examInkSoft.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xs)
        .accessibilityLabel("Transcript is hidden until you finish this attempt")
    }

    private var openBody: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(lesson.transcript.joined(separator: "\n"))
                .font(.examBody(15 * fontScale))
                .foregroundStyle(Color.examInk)
                .lineSpacing(6 * fontScale)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            // Speaker turns read faster with a little air; a raw wall of dialogue is
            // the thing that makes transcripts useless for study.
            Divider().overlay(Color.examRule)
            Text("Turn the transcript on the audio player to follow along while you re-listen.")
                .font(.examBody(12))
                .foregroundStyle(Color.examInkSoft)
        }
    }

    private var sizeControl: some View {
        HStack(spacing: 4) {
            Button {
                fontScale = max(ExamMetrics.minReadingScale, fontScale - 0.1)
            } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .accessibilityLabel("Smaller transcript text")

            Button {
                fontScale = min(ExamMetrics.maxReadingScale, fontScale + 0.1)
            } label: {
                Image(systemName: "textformat.size.larger")
            }
            .accessibilityLabel("Larger transcript text")
        }
        .font(.examBody(13, weight: .semibold))
        .foregroundStyle(Color.examInkSoft)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.examPaperSunk, in: .capsule)
    }
}

/// Passage column for reading, with a size control. Long-form text in a phone-width
/// column at the default size is the most common reading complaint there is.
struct ReadingColumnView: View {
    let paragraphs: [String]
    @State private var scale: Double = 1
    @State private var measured = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Passage")
                    .font(.examDisplay(19))
                    .foregroundStyle(Color.examInk)
                Spacer()
                sizeControl
            }

            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                Text(paragraph)
                    .font(.examBody((17 * scale).rounded()))
                    .foregroundStyle(Color.examInk)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    // The opening line of an academic passage is the topic sentence;
                    // set it in italic Didot so the eye lands there first.
                    .modifier(OpeningLineStyle(isFirst: index == 0))
            }

            if !measured {
                Text("Adjust the size to a comfortable reading size before you start.")
                    .font(.examBody(11))
                    .foregroundStyle(Color.examInkSoft.opacity(0))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .background(Color.examPaperSunk, in: .rect(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(Color.examRule.opacity(0.7), lineWidth: 1)
        )
        .onAppear { measured = true }
    }

    private var sizeControl: some View {
        HStack(spacing: 2) {
            Button {
                scale = max(ExamMetrics.minReadingScale, scale - 0.1)
                Haptics.selection()
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("Smaller passage text")
            .disabled(scale <= ExamMetrics.minReadingScale)

            Button {
                scale = min(ExamMetrics.maxReadingScale, scale + 0.1)
                Haptics.selection()
            } label: {
                Image(systemName: "textformat.size.larger")
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("Larger passage text")
            .disabled(scale >= ExamMetrics.maxReadingScale)
        }
        .font(.examBody(14, weight: .semibold))
        .foregroundStyle(Color.examInkSoft)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.examPaper, in: .capsule)
        .overlay(Capsule().strokeBorder(Color.examRule, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityValue("Text size \(Int(scale * 100)) percent")
    }
}

private struct OpeningLineStyle: ViewModifier {
    let isFirst: Bool

    func body(content: Content) -> some View {
        if isFirst {
            content.font(.examDisplayItalic(17)).padding(.bottom, 2)
        } else {
            content
        }
    }
}