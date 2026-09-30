import SwiftUI
import EnglishCore

/// The dictation input: the play / replay / slow-replay loop, the type field,
/// and — once checked — the reveal.
///
/// Dictation is the one exercise kind where the interaction *is* the exercise,
/// so it gets its own layout rather than the generic text field. The loop is
/// explicit and always in the same place: hear it, type what you heard, check,
/// then hear it again with the answer in front of you.
struct DictationAnswerArea: View {
    @Binding var text: String
    /// The clip to transcribe. `nil` when the content has no audio, which is
    /// shown as a clear problem rather than an inert field.
    let clip: AudioClip?
    var isFocused: FocusState<Bool>.Binding

    @Environment(AudioPlayerModel.self) private var audio
    @State private var isRevealed = false

    var body: some View {
        VStack(spacing: Spacing.md) {
            if let clip {
                // A speech clip is the expected case and has no timeline, so
                // the full `AudioPlayerView` would add a scrubber that does
                // nothing. The quick controls are the right subset here.
                QuickAudioControls(clip: clip)
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity)
                    .glassCard()
            } else {
                Label(
                    "This dictation has no audio. Ask for the sentence, then type it.",
                    systemImage: "speaker.slash"
                )
                .font(AppFont.body(.caption))
                .foregroundStyle(Palette.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }

            TextField(
                "",
                text: $text,
                axis: .vertical
            )
            .font(AppFont.body(.body))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1...6)
            .padding(Spacing.md)
            .frame(minHeight: Metric.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(Palette.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .strokeBorder(Palette.separator, lineWidth: 1)
            )
            .focused(isFocused)
            .submitLabel(.done)
            .accessibilityLabel(Text(verbatim: "What you heard"))
            .accessibilityHint(Text(verbatim: "Double tap to type the sentence exactly as you heard it."))

            if isRevealed, let expected = clip?.text {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("The sentence")
                        .font(AppFont.body(.caption, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                    Text(expected)
                        .font(AppFont.display(.body))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                        .fill(Palette.brandSoft)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: "The sentence is: \(expected)"))
            }
        }
        .onDisappear {
            // Leaving the exercise stops the audio; a dictation that keeps
            // talking after the learner has moved on is a bug, not a feature.
            audio.stop()
        }
    }
}

/// The graded outcome of one exercise: right or wrong, the explanation, the
/// correct answer, and — for text — exactly which words were wrong.
///
/// The diff highlighting is the point of this panel. "Incorrect" tells a learner
/// nothing they can act on; "is *play* should be *is playing*" tells them
/// exactly what to fix. `ExerciseResult.diffs` already carries the
/// word-level alignment, so the panel just renders it — it does no diffing of
/// its own.
struct ResultPanel: View {
    let result: ExerciseResult
    /// The exercise this result belongs to.
    ///
    /// Not optional and not reconstructible: `ExerciseResult` carries the
    /// correct *answer*, whose choice and order payloads are item ids. Without
    /// the exercise there is no way to turn `"a3"` back into the sentence the
    /// learner was meant to pick.
    let exercise: Exercise
    /// The learner's own typed text, for the word-level diff. `nil` for
    /// selection kinds, which have no text to diff.
    let userText: String?
    var onContinue: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header

            if let userText, !result.diffs.isEmpty {
                diffView(userText)
            }

            if !result.explanation.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Why")
                        .font(AppFont.body(.caption, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                    Text(result.explanation)
                        .font(AppFont.body(.subheadline))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            correctAnswer

            if result.xpAwarded > 0 {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(Palette.xp)
                        .accessibilityHidden(true)
                    Text("+\(result.xpAwarded) XP")
                        .font(AppFont.mono(.caption, weight: .bold))
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            if let onContinue {
                PrimaryButton(
                    title: "Continue",
                    symbol: "arrow.right",
                    action: {
                        Haptics.selection()
                        onContinue()
                    }
                )
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(result.isCorrect ? Palette.successSurface : Palette.dangerSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(
                    (result.isCorrect ? Palette.success : Palette.danger).opacity(0.4),
                    lineWidth: 1
                )
        )
        .onAppear {
            // The scale-in is the one moment in an exercise flow that earns a
            // deliberate animation: it marks the moment the answer landed.
            // Under Reduce Motion it is skipped and the panel simply appears.
            guard !reduceMotion else { return }
            withAnimation(Motion.emphatic) { hasAppeared = true }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: result.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(result.isCorrect ? Palette.success : Palette.danger)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.isCorrect ? "Correct" : "Not quite")
                    .font(AppFont.display(.headline))
                    .foregroundStyle(Palette.textPrimary)
                if !result.isCorrect {
                    Text("\(Format.percent(result.accuracy)) of the words matched.")
                        .font(AppFont.body(.caption))
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(verbatim: result.isCorrect
                ? "Correct"
                : "Not quite. \(Format.percent(result.accuracy)) of the words matched.")
        )
    }

    /// The learner's own text with the wrong words marked in place.
    private func diffView(_ userText: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("What you wrote")
                .font(AppFont.body(.caption, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)

            DiffMarkedText(text: userText, diffs: result.diffs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var correctAnswer: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("The answer")
                .font(AppFont.body(.caption, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
            Text(answerText)
                .font(AppFont.display(.body))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "The answer is: \(answerText)"))
    }

    private var answerText: String {
        AnswerDisplay.text(for: result.correctAnswer, exercise: exercise)
    }
}

/// Renders `text` with the tokens named by `diffs` highlighted.
///
/// Each diff token is marked in the learner's own sentence rather than in a
/// side-by-side comparison, because the thing they need to fix is the sentence
/// they wrote. A `substituted` or `extra` word is struck; a `missing` word has
/// no position in the learner's text, so it is appended in the right place as
/// an insertion.
struct DiffMarkedText: View {
    let text: String
    let diffs: [TokenDiff]

    var body: some View {
        // Concatenated `Text` rather than an `HStack` of words: a FlowLayout
        // would break the sentence's own wrapping at large accessibility sizes,
        // and a joined `Text` wraps naturally and stays one accessibility
        // element.
        composed
            .font(AppFont.display(.body))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: spokenSummary))
    }

    private var composed: Text {
        var result = Text("")
        for (index, token) in tokens.enumerated() {
            let mark = diff(for: index)
            let piece = Text(token + (index == tokens.count - 1 ? "" : " "))
            if let mark {
                switch mark.kind {
                case .substituted, .extra:
                    result = result + piece
                        .foregroundColor(Palette.danger)
                        .strikethrough(true, color: Palette.danger)
                case .missing:
                    // Rendered as an insertion at the front of the sentence
                    // when the learner left it out entirely.
                    result = result + Text("[missing: \(mark.expected ?? "")] ")
                        .foregroundColor(Palette.warning)
                        .bold()
                }
            } else {
                result = result + piece
                    .foregroundColor(Palette.textPrimary)
            }
        }
        return result
    }

    private var tokens: [String] {
        text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    /// The diff that lands on `index`, if any.
    ///
    /// `TokenDiff.index` is the position in the *expected* token list for a
    /// `missing` or `substituted` diff and in the *user's* list for an `extra`
    /// one, so a diff is only applied to the learner's own token when the index
    /// is in range and the token actually differs. A mismatched index is
    /// skipped rather than guessed at: highlighting the wrong word teaches the
    /// wrong lesson.
    private func diff(for index: Int) -> TokenDiff? {
        diffs.first { diff in
            switch diff.kind {
            case .extra:
                // An extra word exists in the learner's text at this position.
                index == diff.index && diff.user == tokens[index]
            case .substituted, .missing:
                guard index < tokens.count else { return false }
                guard let user = diff.user else { return diff.kind == .missing && index == 0 }
                return user == tokens[index]
            }
        }
    }

    /// A plain-language version of the marked sentence, because struck-through
    /// and coloured text is not something VoiceOver can convey.
    private var spokenSummary: String {
        let problems = diffs
            .map { diff -> String in
                switch diff.kind {
                case .substituted:
                    return "\(diff.user ?? "a word") should be \(diff.expected ?? "a different word")"
                case .missing:
                    return "you left out \(diff.expected ?? "a word")"
                case .extra:
                    return "\(diff.user ?? "a word") should not be there"
                }
            }
            .joined(separator: ", ")
        return problems.isEmpty ? text : "\(text). \(problems)."
    }
}
