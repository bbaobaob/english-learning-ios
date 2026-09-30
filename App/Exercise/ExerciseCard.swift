import SwiftUI
import EnglishCore

/// What a learner submitted, and how.
///
/// Two cases rather than one `UserResponse` because the two grading entry
/// points in `LearnSession` are separate: `submit(_:)` for a structured
/// response, `submitDictation(_:)` for free text run through the dictation
/// engine with its word-level diff. Collapsing them would force one of the two
/// to be reconstructed from the other, and the dictation diff is the whole
/// point of that path.
enum ExerciseSubmission {
    /// A structured answer: a choice, an order, pairs, or a boolean.
    case response(UserResponse)
    /// Typed text for a dictation or free-text exercise.
    case dictation(String)
}

/// Renders every `ExerciseKind` and reports the learner's answer back.
///
/// One view, not sixteen, and the reason is the contract: the content is
/// authored as JSON with a `kind` discriminator, and a screen lane that has to
/// switch on kind itself will eventually forget a case. The kind-specific
/// interaction is a subview; the surrounding frame — prompt, instruction,
/// answer area, result panel — is identical for all of them, so it is written
/// once.
///
/// The view holds no grading logic. It collects a `UserResponse` and hands it
/// up; `LearnSession` decides what is right.
struct ExerciseCard: View {
    /// The question being asked.
    let exercise: Exercise
    /// Called with the learner's answer. The caller runs it through
    /// `LearnSession` and passes the result back down.
    let onSubmit: (ExerciseSubmission) -> Void
    /// The graded result, or `nil` while the exercise is unanswered. Once
    /// non-nil the input area is replaced by the result panel.
    let result: ExerciseResult?
    /// Called from the result panel's forward button, e.g. to advance
    /// `LearnSession`. `nil` hides the button.
    var onContinue: (() -> Void)?

    @Environment(AudioPlayerModel.self) private var audio
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Interaction state. Held here, not in `LearnSession`, because an answer
    // that has not been submitted is not part of the session's record.
    @State private var selectedIDs: Set<String> = []
    @State private var text: String = ""
    @State private var order: [String] = []
    @State private var pairs: [String: String] = [:]
    @State private var boolean: Bool?
    @State private var focusedLeft: String?
    @FocusState private var isTextFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            prompt
            if !isAnswered {
                // Only rendered when there is something to render: the dictation
                // kind gets its audio inside `DictationAnswerArea`, so showing a
                // second player for it would mean two play buttons for one clip.
                if let translation = exercise.translation, !translation.isEmpty {
                    translationBlock(translation)
                }
                answerArea
                if let clip = exercise.audio, exercise.kind != .dictation {
                    AudioPlayerView(clip: clip)
                        .padding(.top, Spacing.sm)
                }
                submitButton
            } else if let result {
                ResultPanel(
                    result: result,
                    exercise: exercise,
                    userText: isTextual ? text : nil,
                    onContinue: onContinue
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .cardStyle()
        .animation(Motion.accessible(Motion.standard, reduceMotion: reduceMotion), value: isAnswered)
        .onAppear(perform: prepare)
        // A different exercise in the same slot must not inherit the previous
        // one's answer. Keyed on the id, so re-rendering the same exercise
        // keeps what the learner typed.
        .onChange(of: exercise.id) { _, _ in prepare() }
    }

    // MARK: - Prompt

    private var prompt: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                LevelPill(text: exercise.difficulty.rawValue)
                if let audioClip = exercise.audio, exercise.kind == .dictation {
                    Spacer(minLength: 0)
                    SpeakHintButton(text: audioClip.text ?? "")
                }
            }

            Text(exercise.prompt)
                .font(AppFont.display(.title3))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Text(exercise.instruction ?? ExerciseDefaults.instruction(for: exercise.kind))
                .font(AppFont.body(.subheadline))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func translationBlock(_ translation: String) -> some View {
        Text(translation)
            .font(AppFont.body(.subheadline))
            .foregroundStyle(Palette.textSecondary)
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(Palette.field)
            )
            .accessibilityLabel(Text(verbatim: "Vietnamese: \(translation)"))
    }

    // MARK: - Answer area

    @ViewBuilder
    private var answerArea: some View {
        switch exercise.kind {
        case .multipleChoice, .multiSelect, .reading, .listening, .listeningComprehension:
            OptionListView(
                items: exercise.items,
                selectedIDs: $selectedIDs,
                allowsMultiple: exercise.kind == .multiSelect
            )
        case .trueFalse:
            BooleanPairView(selection: $boolean)
        case .matching:
            MatchingGridView(
                items: exercise.items,
                pairs: $pairs,
                focusedID: $focusedLeft
            )
        case .rearrangeWords:
            ReorderWordsView(tokens: $order)
        case .fillInTheBlank, .typeTheAnswer, .sentenceCompletion,
             .errorCorrection, .grammarCorrection, .wordFormation, .translation:
            TextAnswerField(text: $text, prompt: placeholder, isFocused: $isTextFocused)
        case .dictation:
            DictationAnswerArea(
                text: $text,
                clip: exercise.audio,
                isFocused: $isTextFocused
            )
        }
    }

    private var placeholder: String {
        switch exercise.kind {
        case .fillInTheBlank: "Missing word"
        case .wordFormation: "e.g. achievement"
        case .translation: "Type the English sentence"
        default: "Your answer"
        }
    }

    // MARK: - Submit

    private var submitButton: some View {
        PrimaryButton(
            title: exercise.kind == .dictation ? "Check" : "Submit",
            symbol: "checkmark",
            isEnabled: canSubmit,
            action: submit
        )
        .onChange(of: canSubmit) { _, _ in
            if canSubmit { isTextFocused = false }
        }
    }

    /// Whether the learner has given enough of an answer to grade.
    ///
    /// This is a completeness check, not grading: it never looks at the
    /// expected answer, because the view has no business knowing it.
    private var canSubmit: Bool {
        switch exercise.kind {
        case .multipleChoice, .multiSelect, .reading, .listening, .listeningComprehension:
            !selectedIDs.isEmpty
        case .trueFalse:
            boolean != nil
        case .matching:
            // Every item must be paired before the answer means anything, so a
            // half-finished grid cannot be submitted. The count is the item
            // count, not the distinct-key count: the grid's left column is
            // every item, so that is how many pairs a full grid has.
            !exercise.items.isEmpty && pairs.count == exercise.items.count
        case .rearrangeWords:
            !order.isEmpty
        case .fillInTheBlank, .dictation, .typeTheAnswer, .sentenceCompletion,
             .errorCorrection, .grammarCorrection, .wordFormation, .translation:
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func submit() {
        Haptics.selection()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if ExerciseDefaults.isTextual(exercise.kind) {
            onSubmit(.dictation(trimmed))
            return
        }
        switch exercise.kind {
        case .trueFalse:
            if let boolean { onSubmit(.response(.boolean(boolean))) }
        case .matching:
            onSubmit(.response(.pairs(pairs)))
        case .rearrangeWords:
            onSubmit(.response(.order(order)))
        default:
            // Sorted so a multi-select response is order-independent, which is
            // what `ExerciseEngine` compares against.
            onSubmit(.response(.choice(selectedIDs.sorted())))
        }
    }

    // MARK: - State

    private var isAnswered: Bool { result != nil }
    private var isTextual: Bool { ExerciseDefaults.isTextual(exercise.kind) }

    /// Seeds the interaction state for the current exercise.
    ///
    /// A `rearrangeWords` exercise opens with its tokens rotated by one, so the
    /// list is not already in answer order — a list that starts solved gives
    /// the answer away for free. A rotation is stable across launches, so the
    /// exercise looks the same every time the learner opens it.
    private func prepare() {
        selectedIDs = []
        text = ""
        pairs = [:]
        boolean = nil
        focusedLeft = nil
        if exercise.kind == .rearrangeWords {
            let tokens = exercise.items.map { $0.text ?? $0.id }
            order = tokens.count > 1 ? Array(tokens.dropFirst()) + [tokens[0]] : tokens
        } else {
            order = []
        }
    }
}

/// A small speaker button next to a dictation prompt, so the sentence can be
/// heard before the audio bar is even scrolled to.
private struct SpeakHintButton: View {
    let text: String
    @Environment(AudioPlayerModel.self) private var audio

    var body: some View {
        Button {
            Haptics.selection()
            // A multiple of normal speed, not a literal rate — see `SpeechRate`.
            // Slow enough to pick out a word the learner missed the first time.
            audio.speak(text, rate: SpeechRate.scaled(0.75), completion: nil)
        } label: {
            Label("Hear it", systemImage: "speaker.wave.2.fill")
                .font(AppFont.body(.caption, weight: .semibold))
                .foregroundStyle(Palette.brand)
                .padding(.horizontal, Spacing.sm)
                .frame(minHeight: Metric.controlHeight)
                .background(Capsule().fill(Palette.brandSoft))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "Hear the sentence"))
        .accessibilityHint(Text(verbatim: "Plays the sentence slowly."))
    }
}
