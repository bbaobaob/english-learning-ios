import SwiftUI
import EnglishCore
import EnglishStore

// Hear → Type: the app speaks, the learner spells.
//
// The comparison is `DictationEngine.evaluate(userInput:expected:)` and nothing
// else. Case, trailing punctuation, curly quotes and spacing are the engine's
// problem per ARCHITECTURE.md §2 — this screen shows the verdict it returns and
// never looks at the two strings itself.
//
// Replay and slow replay are available as many times as the learner wants, and
// nothing is spent for listening, so the drill rewards listening rather than
// punishing slow learners.

/// The Hear → Type spelling drill.
struct HearTypeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The words to drill, in order.
    let words: [VocabWord]
    /// Shown in the navigation bar.
    let title: String

    @State private var session: HearTypeSession?

    init(words: [VocabWord], title: String) {
        self.words = words
        self.title = title
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let session {
                content(session)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Preparing the drill")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if session == nil, !words.isEmpty {
                session = HearTypeSession(words: words, usesExample: false)
            }
            speakCurrent(session)
        }
    }

    @ViewBuilder
    private func content(_ session: HearTypeSession) -> some View {
        if session.isFinished {
            summary(session)
        } else if let card = session.current {
            drill(session, card)
        } else {
            EmptyStateView(
                symbol: "ear",
                title: "Nothing to hear",
                message: "This drill has no words. Go back to the deck and pick some.",
                actionTitle: "Back to the deck",
                action: { dismiss() }
            )
        }
    }

    // MARK: - Drill

    private func drill(_ session: HearTypeSession, _ card: HearTypeCard) -> some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                progressHeader(session)

                listeningCard(session, card)

                if case .correct = session.answer {
                    correctPanel(session, card)
                        .transition(.opacity)
                } else {
                    TypingPanel(session: session)
                        .transition(.opacity)
                }

                if let result = session.answer.result {
                    wrongPanel(result, session: session, card: card)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: session.answer.result?.isCorrect)
        }
        .scrollDismissesKeyboard(.interactively)
        // The summary pushes word details, so this screen needs the same
        // destination table the tab root declares.
        .navigationDestination(for: VocabRoute.self) { route in
            switch route {
            case .detail(let wordID):
                WordDetailView(wordID: wordID)
            case .review:
                FlashcardView()
            case .hearType(let wordIDs):
                HearTypeView(words: words.filter { wordIDs.contains($0.id) }, title: "Hear → Type")
            case .freeHearType:
                HearTypeView(
                    words: Array(appState.library.allVocabulary.shuffled().prefix(VocabPace.freePracticeLimit)),
                    title: "Free practice"
                )
            case .focusedReview(let wordIDs):
                FlashcardView(focusWordIDs: wordIDs)
            }
        }
    }

    private func progressHeader(_ session: HearTypeSession) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(session.positionLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if session.replays > 0 {
                    Label("\(session.replays) listen\(session.replays == 1 ? "" : "s")", systemImage: "ear")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            ProgressView(value: session.progress)
                .tint(.brand)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Drill progress")
                .accessibilityValue(Text(session.positionLabel))
        }
        .padding(.top, Spacing.sm)
    }

    /// The listening panel: the prompt is deliberately invisible, so the only
    /// way to get the word is to listen.
    private func listeningCard(_ session: HearTypeSession, _ card: HearTypeCard) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(Color.brand)
                .accessibilityHidden(true)

            Text(session.usesExample ? "Listen to the sentence, then type it" : "Listen, then type what you hear")
                .font(AppFont.display(.title3, weight: .semibold))
                .multilineTextAlignment(.center)

            if let topic = card.word.topic {
                VocabTagText(text: topic.split(separator: "-").joined(separator: " "))
            }

            HStack(spacing: Spacing.md) {
                Button {
                    play(session)
                } label: {
                    Label("Play", systemImage: "speaker.wave.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Speaks the word again at normal speed")

                Button {
                    playSlow(session)
                } label: {
                    Label("Slow", systemImage: "tortoise.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Speaks the word again, slowly")
            }
            .tint(.brand)

            Button {
                session.usesExample.toggle()
                speakCurrent(session)
                Haptics.selection()
            } label: {
                Label(
                    session.usesExample ? "Playing the example sentence" : "Playing the word",
                    systemImage: "text.bubble"
                )
                .font(.footnote)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.brand)
            .accessibilityHint("Switches between the single word and its example sentence")
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
        .cardStyle()
    }

}

/// The typed-answer panel, split out so it can hold a `@Bindable` reference to
/// the session: the text field needs a two-way binding, the rest does not.
private struct TypingPanel: View {
    @Bindable var session: HearTypeSession
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            TextField("Type what you hear", text: $session.input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .font(AppFont.mono(20, weight: .medium))
                .padding(Spacing.md)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Radius.chip))
                .focused($isFocused)
                .accessibilityLabel("Your answer")
                .onSubmit { check() }

            PrimaryButton(
                title: "Check",
                symbol: "checkmark",
                isEnabled: !session.input.isEmpty,
                action: check
            )
            .frame(maxWidth: .infinity)

            Text(session.usesExample
                ? "Type the sentence you just heard."
                : "Capital letters and trailing full stops are ignored.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(Spacing.md)
        .cardStyle()
        .onAppear { isFocused = true }
    }

    /// Grades through the engine and gives the learner a distinct feel per verdict.
    private func check() {
        let answer = session.check()
        switch answer {
        case .correct: Haptics.success()
        case .wrong: Haptics.warning()
        case .typing: break
        }
    }

    /// The right answer, plainly, with the example for context.
    private func correctPanel(_ session: HearTypeSession, _ card: HearTypeCard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.success)
                Text("Correct")
                    .font(AppFont.display(.title3, weight: .bold))
            }

            Text(card.word.word)
                .font(AppFont.display(.title2, weight: .bold))
                .accessibilityLabel(card.word.word)

            Text(card.word.meaning)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let example = card.word.example {
                Text(example)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryButton(
                title: session.isFinished ? "Finish" : "Next word",
                symbol: "arrow.right",
                isEnabled: true
            ) {
                session.advance()
                speakCurrent(session)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .cardStyle()
    }

    /// The wrong-answer panel: the engine's summary, the correct spelling, the
    /// difference between the two, and the three ways forward.
    private func wrongPanel(_ result: DictationResult, session: HearTypeSession, card: HearTypeCard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.danger)
                Text("Not quite")
                    .font(AppFont.display(.title3, weight: .bold))
                Spacer()
                Text(Text(result.accuracy, format: .percent.precision(.fractionLength(0))))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let summary = result.firstErrorSummary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // `result.expected` is the engine's own canonical string, which in
            // example mode is the sentence — not the bare headword.
            differenceView(result, written: session.input)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(session.usesExample ? "Correct sentence" : "Correct spelling")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Text(result.expected)
                        .font(AppFont.mono(18, weight: .semibold))
                        .textSelection(.enabled)
                    VocabSpeakButton(
                        text: result.expected,
                        rate: 0.4,
                        accessibilityLabel: "Hear the correct answer",
                        size: 32
                    )
                }
            }

            // In example mode the correct sentence is already shown above.
            if let example = card.word.example, !session.usesExample {
                Text(example)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Spacing.sm) {
                SecondaryButton(title: "Hear it again", symbol: "speaker.wave.2") {
                    play(session)
                }
                SecondaryButton(title: "Slow", symbol: "tortoise.fill") {
                    playSlow(session)
                }
            }

            HStack(spacing: Spacing.sm) {
                Button {
                    session.input = ""
                    Haptics.warning()
                } label: {
                    Label("Try again", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Clears your answer so you can spell it again")

                Button {
                    session.advance()
                    speakCurrent(session)
                } label: {
                    Label("Skip", systemImage: "forward.end.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Moves on without answering this word")
            }
            .tint(.brand)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .cardStyle()
    }

    /// The engine's diffs, rendered word by word. Tokens come from the engine's
    /// own normalisation, so `Play` and `playing` show as one substitution.
    private func differenceView(_ result: DictationResult, written raw: String) -> some View {
        let normalizer = AnswerNormalizer()
        let written = normalizer.tokens(raw)
        let expected = normalizer.tokens(result.expected)

        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Your answer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            diffRow(written, result: result)

            Text("Correct")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            expectedRow(expected, result: result)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Highlights the learner's own tokens.
    ///
    /// Only `TokenDiff.extra` carries an index into the *learner's* tokens —
    /// `.substituted` and `.missing` index into the expected list — so extras are
    /// the only ones safely coloured here. Everything else stays neutral rather
    /// than being pointed at by a number that means something else.
    private func diffRow(_ written: [String], result: DictationResult) -> some View {
        let extras = Set(result.diffs.compactMap { diff -> Int? in
            diff.kind == .extra ? diff.index : nil
        })
        return tokenRow(written) { index in
            extras.contains(index) ? (written[index], Color.danger) : (written[index], Color.secondary)
        }
    }

    private func expectedRow(_ expected: [String], result: DictationResult) -> some View {
        let flagged = Set(result.diffs.compactMap { diff -> Int? in
            diff.kind == .substituted || diff.kind == .missing ? diff.index : nil
        })
        return tokenRow(expected) { index in
            flagged.contains(index) ? (expected[index], Color.success) : (expected[index], Color.secondary)
        }
    }

    private func tokenRow(_ tokens: [String], style: (Int) -> (String, Color)) -> some View {
        // ponytail: a wrapping `HStack` would need a layout pass to reflow;
        // `Text` concatenation wraps for free and the per-token colouring is
        // what actually needs the pieces.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 90), spacing: Spacing.xs)],
            alignment: .leading,
            spacing: Spacing.xs
        ) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                let (text, color) = style(index)
                Text(text)
                    .font(AppFont.mono(15, weight: .medium))
                    .foregroundStyle(color)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12), in: .rect(cornerRadius: 6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Summary

    private func summary(_ session: HearTypeSession) -> some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: session.accuracy >= 0.8 ? "checkmark.seal.fill" : "ear.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(session.accuracy >= 0.8 ? Color.success : Color.brand)
                    Text("Drill complete")
                        .font(AppFont.display(.largeTitle, weight: .bold))
                    Text("\(session.firstTryCount) of \(session.total) words spelled correctly first try.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Spacing.xl)
                .frame(maxWidth: .infinity)

                HStack(spacing: Spacing.md) {
                    ProgressRing(
                        progress: session.accuracy,
                        lineWidth: 12,
                        tint: session.accuracy >= 0.8 ? .success : .brand,
                        label: "Accuracy"
                    )
                    .frame(width: 108, height: 108)
                    .accessibilityLabel("Accuracy")
                    .accessibilityValue(Text(session.accuracy, format: .percent.precision(.fractionLength(0))))

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(Text(session.accuracy, format: .percent.precision(.fractionLength(0))))
                            .font(AppFont.display(.title, weight: .bold))
                            .monospacedDigit()
                        Text("\(session.shaky.count) to keep practising")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Listening costs nothing here — replay as many times as you need.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Spacing.md)
                .cardStyle()

                if !session.shaky.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        SectionHeader(
                            title: "Keep practising",
                            subtitle: "Words you missed at least once. Tap one to open it.",
                            actionTitle: nil,
                            action: nil
                        )
                        VStack(spacing: Spacing.xs) {
                            ForEach(session.shaky, id: \.self) { wordID in
                                if let word = words.first(where: { $0.id == wordID }) {
                                    NavigationLink(value: VocabRoute.detail(word.id)) {
                                        HStack(spacing: Spacing.md) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(word.word)
                                                    .font(AppFont.display(.body, weight: .semibold))
                                                    .foregroundStyle(.primary)
                                                Text(word.meaning)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer(minLength: Spacing.sm)
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                        .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.vertical, Spacing.xs)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityHint("Opens the word")
                                }
                            }
                        }
                        .padding(Spacing.md)
                        .cardStyle()
                    }
                } else {
                    EmptyStateView(
                        symbol: "sparkles",
                        title: "Nothing to practise",
                        message: "You spelled every word correctly first time. Come back when you want another set.",
                        actionTitle: nil,
                        action: nil
                    )
                }

                PrimaryButton(title: "Done", symbol: "checkmark", isEnabled: true, action: { dismiss() })
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .vocabAurora()
    }

    // MARK: - Playback and grading

    /// Speaks the current prompt, marking that one listen happened.
    private func play(_ session: HearTypeSession) {
        session.noteReplay()
        speakCurrent(session)
    }

    private func playSlow(_ session: HearTypeSession) {
        session.noteReplay()
        guard let card = session.current else { return }
        let text = session.spokenText ?? card.word.word
        Haptics.selection()
        appState.speech.speak(text, rate: 0.3, completion: nil)
    }

    /// Speaks whatever the session is currently set to: the word, or the example
    /// sentence when the learner has switched modes.
    private func speakCurrent(_ session: HearTypeSession?) {
        guard let session, let text = session.spokenText else { return }
        appState.speech.speak(text, rate: session.usesExample ? 0.45 : 0.5, completion: nil)
    }
}