import SwiftUI
import UIKit
import EnglishCore
import EnglishStore

// The core study surface: one word, front then back, then a 1–4 self-rating.
//
// The rating buttons are the whole interaction and are always on screen. Swipes
// are an accelerator layered on top, so nothing here depends on a gesture being
// discovered, and Reduce Motion swaps content without moving anything.

/// A spaced-repetition flashcard session.
struct FlashcardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    /// Explicit words to study. Empty means "whatever is due today".
    let focusWordIDs: [String]

    @State private var session: FlashcardSession?

    /// - Parameters:
    ///   - focusWordIDs: Word ids to study. Empty falls back to the due queue.
    ///   - onFinish: Called when the learner leaves from the summary.
    init(focusWordIDs: [String] = []) {
        self.focusWordIDs = focusWordIDs
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
                    .accessibilityLabel("Preparing your cards")
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .task { buildSession() }
    }

    @ViewBuilder
    private func content(_ session: FlashcardSession) -> some View {
        if session.isFinished {
            FlashcardSummaryView(session: session) {
                session.recordSession()
                dismiss()
            }
        } else if let card = session.current {
            cardBody(session, card)
        } else {
            EmptyStateView(
                symbol: "rectangle.stack.badge.person.crop",
                title: "No words to study",
                message: "There is nothing in this session. Go back to the deck and pick some words.",
                actionTitle: "Back to the deck",
                action: { dismiss() }
            )
        }
    }

    /// Builds the session once, from whatever the store knows right now.
    private func buildSession() {
        guard session == nil else { return }
        let library = appState.library
        let store = appState.store

        let words: [VocabWord]
        if !focusWordIDs.isEmpty {
            words = focusWordIDs.compactMap { library.vocabWord($0) }
        } else {
            let dueWords = VocabSchedule.dueToday(from: store)
                .compactMap { library.vocabWord($0.refID) }
            words = dueWords.isEmpty
                ? Array(library.allVocabulary.shuffled().prefix(VocabPace.freePracticeLimit))
                : dueWords
        }

        guard !words.isEmpty else { return }
        session = FlashcardSession(words: words, store: store)
    }

    // MARK: - Card

    private func cardBody(_ session: FlashcardSession, _ card: VocabCard) -> some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                progressHeader(session)
                flashcard(session, card)
                if session.isRevealed {
                    ratingControls(session)
                        .transition(.opacity)
                } else {
                    showAnswerButton(session)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: session.isRevealed)
        }
        // Swipe is an accelerator only; every action is also a button below.
        .gesture(swipe(session))
    }

    private func progressHeader(_ session: FlashcardSession) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(session.positionLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Text(session.progress, format: .percent.precision(.fractionLength(0))))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            ProgressView(value: session.progress)
                .tint(.brand)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Session progress")
                .accessibilityValue(Text(session.positionLabel))
        }
        .padding(.top, Spacing.sm)
    }

    private func flashcard(_ session: FlashcardSession, _ card: VocabCard) -> some View {
        VStack(spacing: Spacing.lg) {
            if session.isRevealed {
                back(session, card)
            } else {
                front(session, card)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
        .cardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(session.isRevealed ? "\(card.word.word), answer showing" : "\(card.word.word), question")
    }

    private func front(_ session: FlashcardSession, _ card: VocabCard) -> some View {
        VStack(spacing: Spacing.md) {
            VocabSpeakButton(
                text: card.word.audio?.text ?? card.word.word,
                rate: card.word.audio?.speakingRate ?? 0.5,
                accessibilityLabel: "Hear \(card.word.word)",
                size: 52
            )
            .padding(.top, Spacing.sm)

            VocabWordText(text: card.word.word)

            if let ipa = card.word.ipa {
                VocabIPAText(ipa: ipa)
            }

            Text("Recall the meaning, then turn the card over.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        // Extra tap target for anyone who cannot aim at a small control; the
        // Show answer button below does the same job for VoiceOver.
        .onTapGesture { reveal(session) }
        .accessibilityAction(named: "Show answer") { reveal(session) }
    }

    private func back(_ session: FlashcardSession, _ card: VocabCard) -> some View {
        VStack(spacing: Spacing.md) {
            VocabWordText(text: card.word.word)

            if let ipa = card.word.ipa {
                VocabIPAText(ipa: ipa)
            }

            Text(card.word.meaning)
                .font(AppFont.display(.title3, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Spacing.xs)

            Divider()

            if let example = card.word.example {
                VStack(spacing: Spacing.xs) {
                    Button {
                        Haptics.selection()
                        appState.speech.speak(example, rate: 0.45, completion: nil)
                    } label: {
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Text(example)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "speaker.wave.2")
                                .font(.caption)
                                .foregroundStyle(Color.brand)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hear the example: \(example)")

                    if let vi = card.word.exampleVI {
                        Text(vi)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            wordCloud(title: "Synonyms", words: card.word.synonyms)
            wordCloud(title: "Collocations", words: card.word.collocations)
        }
        .frame(maxWidth: .infinity)
    }

    private func wordCloud(title: String, words: [String]) -> some View {
        Group {
            if !words.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 110), spacing: Spacing.xs)],
                        alignment: .leading,
                        spacing: Spacing.xs
                    ) {
                        ForEach(words, id: \.self) { phrase in
                            VocabTagText(text: phrase)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Controls

    private func showAnswerButton(_ session: FlashcardSession) -> some View {
        Button {
            reveal(session)
        } label: {
            Label("Show answer", systemImage: "eye.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(Color.brand, in: .capsule)
                .vocabGlass(cornerRadius: Radius.pill)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Turns the card over to show the meaning")
    }

    private func reveal(_ session: FlashcardSession) {
        guard !session.isRevealed else { return }
        session.isRevealed = true
        Haptics.selection()
    }

    /// The 1–4 rating row. Always visible once the answer is up, always a real
    /// button, always labelled in words as well as numbers.
    private func ratingControls(_ session: FlashcardSession) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("How well did you know it?")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: Spacing.sm) {
                ForEach(GradeButton.allCases) { option in
                    Button {
                        rate(session, option)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: option.symbol)
                                .font(.caption)
                            Text("\(option.rating)")
                                .font(AppFont.display(.title3, weight: .bold))
                            Text(option.title)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(option.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(option.tint.opacity(0.14), in: .rect(cornerRadius: Radius.chip))
                        .contentShape(.rect)
                        // The rating row is the one control that floats over the
                        // card, so it is the one that gets the glass treatment.
                        // Applied last, after the layout that sizes it.
                        .vocabGlass(cornerRadius: Radius.chip)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.rating), \(option.title)")
                    .accessibilityHint(option.hint)
                }
            }

            Text("Rating honestly is what makes the schedule work. Rating a forgotten word \"good\" only hides it.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .cardStyle()
    }

    private func rate(_ session: FlashcardSession, _ option: GradeButton) {
        Haptics.forGrade(option.grade)
        session.grade(option.grade)
        UIAccessibility.post(notification: .announcement, argument: "\(option.title). Next card.")
    }

    /// Swipe left to reveal (then to rate "again"), swipe right to rate "good".
    ///
    /// ponytail: a plain `DragGesture` with a horizontal bias test is enough for
    /// four discrete targets; a `UISwipeGestureRecognizer` subclass would buy
    /// nothing here because every action is already a button.
    private func swipe(_ session: FlashcardSession) -> some Gesture {
        DragGesture(minimumDistance: 60)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0 {
                    if session.isRevealed {
                        session.grade(.again)
                    } else {
                        reveal(session)
                    }
                } else if session.isRevealed {
                    session.grade(.good)
                } else {
                    reveal(session)
                }
            }
    }
}

// MARK: - Summary

/// The end-of-session screen: what happened, and what is now due later.
private struct FlashcardSummaryView: View {
    let session: FlashcardSession
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.success)
                    Text("Session complete")
                        .font(AppFont.display(.largeTitle, weight: .bold))
                    Text(summaryLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Spacing.xl)
                .frame(maxWidth: .infinity)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Spacing.md)], spacing: Spacing.md) {
                    StatCard(
                        title: "Rated",
                        value: "\(session.outcomes.count)",
                        caption: "cards",
                        symbol: "rectangle.stack.fill",
                        tint: .brand
                    )
                    StatCard(
                        title: "Still due",
                        value: "\(session.stillDue.count)",
                        caption: "come back today",
                        symbol: "clock.badge.exclamationmark",
                        tint: .warning
                    )
                    StatCard(
                        title: "Scheduled",
                        value: "\(session.scheduledLater.count)",
                        caption: "due tomorrow or later",
                        symbol: "calendar.badge.checkmark",
                        tint: .success
                    )
                }

                if !session.scheduledLater.isEmpty {
                    outcomeCard(
                        title: "Now due later",
                        subtitle: "These left today's queue — the scheduler spaced them out for you.",
                        outcomes: session.scheduledLater,
                        symbol: "calendar"
                    )
                }

                if !session.stillDue.isEmpty {
                    outcomeCard(
                        title: "Still due today",
                        subtitle: "You rated these \"did not know\", so they stay in the queue.",
                        outcomes: session.stillDue,
                        symbol: "arrow.uturn.backward.circle.fill",
                        tint: .warning
                    )
                }

                PrimaryButton(title: "Done", symbol: "checkmark", isEnabled: true, action: onDone)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .vocabAurora()
    }

    private func outcomeCard(
        title: String,
        subtitle: String,
        outcomes: [FlashcardOutcome],
        symbol: String,
        tint: Color = .success
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: title, subtitle: subtitle, actionTitle: nil, action: nil)
            VStack(spacing: Spacing.xs) {
                ForEach(outcomes) { outcome in
                    HStack(spacing: Spacing.md) {
                        Image(systemName: symbol)
                            .font(.caption)
                            .foregroundStyle(tint)
                        Text(outcome.card.word.word)
                            .font(AppFont.display(.body, weight: .semibold))
                        Spacer(minLength: Spacing.sm)
                        Text(outcome.rescheduled.dueDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Spacing.xs)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(Spacing.md)
            .cardStyle()
        }
    }

    private var summaryLine: String {
        let rated = session.outcomes.count
        guard rated > 0 else { return "No cards were rated." }
        let later = session.scheduledLater.count
        return later == rated
            ? "Every word left today's queue. See you tomorrow."
            : "\(later) of \(rated) words are scheduled for a later day."
    }
}

// MARK: - Rating button model

/// The 1–4 self-rating, mapped onto the SM-2 scale.
///
/// This type is the single place where the number on the button and the
/// `SpacedRepetition.Grade` handed to the scheduler are declared together, so
/// they cannot drift apart.
enum GradeButton: Int, CaseIterable, Identifiable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    var id: Int { rawValue }

    /// The SM-2 quality grade handed to `SpacedRepetition.schedule(_:grade:)`.
    var grade: SpacedRepetition.Grade {
        switch self {
        case .again: .again
        case .hard: .hard
        case .good: .good
        case .easy: .easy
        }
    }

    /// The big number on the button.
    var rating: Int { rawValue }

    var title: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }

    var hint: String {
        switch self {
        case .again: "I did not know this. It stays in today's queue."
        case .hard: "I remembered, but slowly. A short interval."
        case .good: "I knew it. The usual interval."
        case .easy: "Instantly. A longer interval."
        }
    }

    var symbol: String {
        switch self {
        case .again: "arrow.counterclockwise"
        case .hard: "tortoise.fill"
        case .good: "checkmark"
        case .easy: "hare.fill"
        }
    }

    var tint: Color {
        switch self {
        case .again: .danger
        case .hard: .warning
        case .good: .brand
        case .easy: .success
        }
    }
}

extension Haptics {
    /// One haptic per rating, so the choice is felt as well as seen.
    static func forGrade(_ grade: SpacedRepetition.Grade) {
        switch grade {
        case .again: Haptics.failure()
        case .hard: Haptics.warning()
        case .good: Haptics.success()
        case .easy: Haptics.success()
        }
    }
}