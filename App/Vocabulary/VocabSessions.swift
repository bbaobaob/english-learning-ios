import Foundation
import SwiftUI
import EnglishCore
import EnglishStore

// The two study sessions in this lane, as small observable view-models.
//
// The rule the lane follows: a session decides *when to move on* and *what to
// show next*; it never decides what a grade means or when a word comes back.
// Grading goes through `SpacedRepetition.schedule(_:grade:)`, and the resulting
// item is written through `ProgressStore.upsertReview(_:)`, so the tab can never
// drift from what the rest of the app schedules.

// MARK: - Shared

/// One word being studied, paired with the schedule it will write back.
struct VocabCard: Identifiable {
    let word: VocabWord
    /// The schedule before this card is graded, used to seed the card's own copy.
    let item: ReviewItem

    var id: String { word.id }
}

// MARK: - Flashcards

/// One graded card and the item it became.
struct FlashcardOutcome: Identifiable {
    let card: VocabCard
    let grade: SpacedRepetition.Grade
    /// The item written back to the store.
    let rescheduled: ReviewItem

    var id: String { card.id }

    /// Whether this card is off the books for today.
    ///
    /// Read from the scheduler's own output: `intervalDays == 0` is exactly the
    /// state `schedule(_:grade:)` leaves behind for `Grade.again`, which places
    /// the due date at "now". Anything with a real interval comes back later.
    var leavesToday: Bool { rescheduled.intervalDays > 0 }
}

/// Drives ``FlashcardView``: which card is showing, how it was rated, and what
/// the session produced.
@Observable
@MainActor
final class FlashcardSession {
    /// The cards, in study order.
    private(set) var cards: [VocabCard]
    /// Index of the card being shown; equals `cards.count` once finished.
    var index = 0
    /// Every graded card, in the order it was graded.
    private(set) var outcomes: [FlashcardOutcome] = []
    /// Whether the learner sees the answer. Reset for every card.
    var isRevealed = false

    private let store: ProgressStore
    private let scheduler = SpacedRepetition()

    init(words: [VocabWord], store: ProgressStore) {
        self.store = store
        self.cards = words.map { VocabCard(word: $0, item: VocabSchedule.item(for: $0.id, in: VocabSchedule.all(from: store))) }
    }

    var total: Int { cards.count }

    /// The card on screen, or `nil` once every card is graded.
    var current: VocabCard? { index < cards.count ? cards[index] : nil }

    /// How far through the session the learner is, in `0...1`.
    var progress: Double {
        total == 0 ? 1 : Double(index) / Double(total)
    }

    /// Whether the session has graded every card.
    var isFinished: Bool { index >= cards.count }

    /// The card label shown in the progress line, e.g. `"4 of 12"`.
    var positionLabel: String { "\(min(index + 1, total)) of \(total)" }

    /// Grades the visible card and advances.
    ///
    /// The 1–4 buttons map straight onto the SM-2 scale: `1` is
    /// `Grade.again` ("I did not know it"), `2` is `Grade.hard`, `3` is
    /// `Grade.good`, `4` is `Grade.easy`. `schedule(_:grade:)` owns the interval
    /// and ease arithmetic; the rescheduled item goes straight to
    /// `upsertReview(_:)`, which also refreshes the word's `VocabState`.
    ///
    /// - Parameter grade: The learner's self-rating.
    /// - Returns: The outcome, or `nil` when the session is already finished.
    @discardableResult
    func grade(_ grade: SpacedRepetition.Grade) -> FlashcardOutcome? {
        guard let card = current else { return nil }
        let rescheduled = scheduler.schedule(card.item, grade: grade)
        store.upsertReview(rescheduled)
        let outcome = FlashcardOutcome(card: card, grade: grade, rescheduled: rescheduled)
        outcomes.append(outcome)
        index += 1
        isRevealed = false
        return outcome
    }

    /// How many cards were rated `again`, i.e. still due today.
    var stillDue: [FlashcardOutcome] { outcomes.filter { !$0.leavesToday } }

    /// The cards that now come back on a later day, so the summary can say so.
    var scheduledLater: [FlashcardOutcome] { outcomes.filter(\.leavesToday) }

    /// Records the finished session against the streak and XP totals.
    ///
    /// The XP comes from ``XPEngine``, the same engine every graded exercise
    /// session goes through. This used to award `total * 5` — a flat rate that
    /// ignored *how* the cards were graded, so a session the learner found hard
    /// paid the same as one they found easy, and the app had a second XP source
    /// the engine knew nothing about. Rating a card `again` pays nothing, which
    /// is the point: the learner is being asked to review the words they missed.
    func recordSession() {
        let minutes = max(1, Int((Double(total) * Double(VocabPace.secondsPerWord) / 60).rounded(.up)))

        let graded = outcomes.count
        guard graded > 0 else {
            // Nothing was rated, so nothing is owed. Registering the time still
            // keeps the streak honest: the learner was here.
            store.registerStudy(minutes: minutes, xp: 0, kind: .review)
            return
        }

        let engine = XPEngine()
        let streakDays = store.streak().current
        // `leavesToday` is the scheduler's own verdict: a card rated `again`
        // comes back today and is not a success.
        let correct = outcomes.filter(\.leavesToday).count
        let accuracy = Double(correct) / Double(graded)
        let xp = outcomes.reduce(0) { sum, outcome in
            sum + engine.award(
                base: outcome.leavesToday ? Self.xpPerCard : 0,
                streakDays: streakDays,
                accuracy: accuracy
            )
        }

        store.registerStudy(minutes: minutes, xp: xp, kind: .review)
    }

    /// XP for one correctly rated card.
    ///
    /// Matches the per-exercise award in the content model, so a vocabulary
    /// card and a graded exercise are worth the same thing and a learner's
    /// daily total means one number.
    private static let xpPerCard = 10
}

// MARK: - Hear → Type

/// One word in the Hear → Type drill.
struct HearTypeCard: Identifiable {
    let word: VocabWord
    /// The text the learner has to produce.
    var expected: String { word.word }

    var id: String { word.id }
}

/// The state of one Hear → Type answer.
enum HearTypeAnswer {
    /// Nothing typed yet, or the learner has not pressed Check.
    case typing
    /// The engine accepted the spelling.
    case correct
    /// The engine rejected it; carries the verdict for display.
    case wrong(DictationResult)

    /// The verdict to show when the learner presses Check.
    var result: DictationResult? {
        if case .wrong(let result) = self { return result }
        return nil
    }
}

/// Drives ``HearTypeView``: what is being heard, what was typed, and the verdict.
///
/// Every comparison goes through `DictationEngine.evaluate(userInput:expected:)`,
/// which folds case, punctuation, diacritics and spacing per ARCHITECTURE.md §2.
/// The screen never looks at the two strings itself.
@Observable
@MainActor
final class HearTypeSession {
    /// The cards, in drill order.
    private(set) var cards: [HearTypeCard]
    /// Index of the card being drilled.
    var index = 0
    /// What the learner has typed for the current card.
    var input = ""
    /// The verdict for the current card.
    private(set) var answer: HearTypeAnswer = .typing
    /// Whether the learner is drilling the example sentence instead of the word.
    var usesExample = false
    /// How many times the current card has been heard.
    private(set) var replays = 0
    /// Word ids missed at least once, so the summary can point at them.
    private(set) var shaky: [String] = []
    /// How many Check presses the engine has graded.
    private(set) var attempts = 0
    /// How many of those the engine accepted.
    private(set) var passes = 0

    private let engine = DictationEngine()

    /// - Parameters:
    ///   - words: The words to drill, in order.
    ///   - usesExample: Whether to speak the example sentence rather than the word.
    init(words: [VocabWord], usesExample: Bool) {
        self.cards = words.map { HearTypeCard(word: $0) }
        self.usesExample = usesExample
    }

    var total: Int { cards.count }

    /// The card on screen, or `nil` once the drill is done.
    var current: HearTypeCard? { index < cards.count ? cards[index] : nil }

    var isFinished: Bool { index >= cards.count }

    /// How far through the drill the learner is, in `0...1`.
    var progress: Double {
        total == 0 ? 1 : Double(index) / Double(total)
    }

    /// The card label shown in the progress line, e.g. `"3 of 8"`.
    var positionLabel: String { "\(min(index + 1, total)) of \(total)" }

    /// The share of graded answers the engine accepted, in `0...1`.
    ///
    /// Counts every Check press, so a retry after a mistake counts as an
    /// attempt too — which is exactly what the learner experienced.
    var accuracy: Double {
        attempts == 0 ? 0 : Double(passes) / Double(attempts)
    }

    /// How many words were spelled correctly on the very first Check.
    var firstTryCount: Int { cards.count - shaky.count }

    /// What is being spoken for the current card, or `nil` once finished.
    var spokenText: String? {
        guard let card = current else { return nil }
        if usesExample, let example = card.word.example { return example }
        return card.word.audio?.text ?? card.word.word
    }

    /// Counts one more listen of the current card.
    func noteReplay() { replays += 1 }

    /// Grades what the learner typed, via the engine.
    ///
    /// - Returns: The verdict, so a caller can drive haptics without re-reading state.
    func check() -> HearTypeAnswer {
        guard let card = current else { return .typing }
        let result = engine.evaluate(userInput: input, expected: expected(for: card))
        attempts += 1
        if result.isCorrect {
            answer = .correct
            passes += 1
        } else {
            answer = .wrong(result)
            if !shaky.contains(card.id) { shaky.append(card.id) }
        }
        return answer
    }

    /// What the learner has to produce for this card.
    ///
    /// In example mode the prompt *is* the example sentence, so that is what is
    /// expected back — speaking the sentence and grading against the bare
    /// headword would be unanswerable.
    private func expected(for card: HearTypeCard) -> String {
        if usesExample, let example = card.word.example { return example }
        return card.expected
    }

    /// Clears the typed text and verdict for the next card.
    func advance() {
        index += 1
        input = ""
        answer = .typing
        replays = 0
    }
}
