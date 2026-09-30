import Foundation

/// Anything the learner can answer an exercise with.
public enum UserResponse: Sendable, Equatable {
    case text(String)
    case choice([String])
    case order([String])
    case pairs([String: String])
    case boolean(Bool)
}

/// The verdict for one graded exercise.
public struct ExerciseResult: Sendable, Equatable {
    public let exerciseID: String
    public let isCorrect: Bool
    /// `1.0` when correct; word-level for text kinds, selected-fraction for multiSelect,
    /// matched-pair fraction for matching. Always `0` when wrong for pure-choice kinds.
    public let accuracy: Double
    public let correctAnswer: Answer
    public let explanation: String
    /// Token-level feedback for text and dictation kinds; empty otherwise.
    public let diffs: [TokenDiff]
    public let xpAwarded: Int

    /// Matching keys the learner got wrong, with what they chose. Empty for every other kind.
    public let wrongPairs: [WrongPair]
    /// Correct option ids the learner did not select (multiSelect only).
    public let missedChoiceIDs: [String]
    /// Option ids the learner selected that are not correct (multiSelect only).
    public let extraChoiceIDs: [String]
    /// First index where a word-order answer diverges from the expected order (rearrangeWords only).
    public let firstDivergenceIndex: Int?

    /// The first seven parameters are the frozen §2 signature, in that exact order; the rest are
    /// additive and defaulted, so other modules can still call the seven-argument form.
    public init(
        exerciseID: String,
        isCorrect: Bool,
        accuracy: Double,
        correctAnswer: Answer,
        explanation: String,
        diffs: [TokenDiff],
        xpAwarded: Int,
        wrongPairs: [WrongPair] = [],
        missedChoiceIDs: [String] = [],
        extraChoiceIDs: [String] = [],
        firstDivergenceIndex: Int? = nil
    ) {
        self.exerciseID = exerciseID
        self.isCorrect = isCorrect
        self.accuracy = accuracy
        self.correctAnswer = correctAnswer
        self.explanation = explanation
        self.diffs = diffs
        self.xpAwarded = xpAwarded
        self.wrongPairs = wrongPairs
        self.missedChoiceIDs = missedChoiceIDs
        self.extraChoiceIDs = extraChoiceIDs
        self.firstDivergenceIndex = firstDivergenceIndex
    }
}

/// One key of a matching/map exercise paired with what the learner chose.
public struct WrongPair: Sendable, Equatable, Identifiable {
    public var id: String { key }
    public let key: String
    public let user: String?
    public let expected: String

    public init(key: String, user: String? = nil, expected: String) {
        self.key = key
        self.user = user
        self.expected = expected
    }
}

/// Grades an ``Exercise`` against a ``UserResponse``, one branch per ``ExerciseKind``.
///
/// Foundation only: no SwiftUI, no SwiftData, no AVFoundation.
public struct ExerciseEngine: Sendable {
    private let normalizer: AnswerNormalizer
    private let dictation: DictationEngine

    public init(normalizer: AnswerNormalizer = AnswerNormalizer()) {
        self.normalizer = normalizer
        self.dictation = DictationEngine(normalizer: normalizer)
    }

    /// Grades `response` against `exercise`, dispatching on `exercise.kind`.
    public func check(_ exercise: Exercise, response: UserResponse) -> ExerciseResult {
        let result: ExerciseResult
        switch exercise.kind {
        case .multipleChoice, .reading, .listening, .listeningComprehension:
            result = checkChoice(exercise, response: response, allowPartial: false)
        case .multiSelect:
            result = checkChoice(exercise, response: response, allowPartial: true)
        case .trueFalse:
            result = checkBoolean(exercise, response: response)
        case .matching:
            result = checkMatching(exercise, response: response)
        case .rearrangeWords:
            result = checkOrder(exercise, response: response)
        case .dictation:
            result = checkText(exercise, response: response)
        case .fillInTheBlank, .typeTheAnswer, .sentenceCompletion, .errorCorrection,
             .wordFormation, .translation, .grammarCorrection:
            result = checkText(exercise, response: response)
        }
        return result
    }

    /// Grades typed dictation. Equivalent to ``check`` with `.text`, kept for call-site clarity.
    public func checkDictation(_ exercise: Exercise, userInput: String) -> ExerciseResult {
        check(exercise, response: .text(userInput))
    }

    // MARK: - Choice

    /// Set comparison of selected ids against `Answer.choice`. Option count is irrelevant: three
    /// options (IELTS) and four (grammar topics) grade identically, and exactly one id is expected.
    private func checkChoice(_ exercise: Exercise, response: UserResponse, allowPartial: Bool) -> ExerciseResult {
        let expected = Set(expectedChoice(exercise))
        let selected = Set(response.asChoice ?? [])
        let missed = expected.subtracting(selected).sorted()
        let extra = selected.subtracting(expected).sorted()
        let isCorrect = !expected.isEmpty && expected == selected
        // A pure choice question has no meaningful partial credit: either the set is right or it is
        // not. multiSelect gets a ratio because "picked 2 of 3" is real feedback.
        let accuracy = isCorrect ? 1.0 : (allowPartial && !expected.isEmpty ? Double(expected.count - missed.count) / Double(expected.count) : 0)
        return ExerciseResult(
            exerciseID: exercise.id,
            isCorrect: isCorrect,
            accuracy: accuracy,
            correctAnswer: exercise.answer,
            explanation: exercise.explanation,
            diffs: [],
            xpAwarded: isCorrect ? exercise.xp : 0,
            missedChoiceIDs: missed,
            extraChoiceIDs: extra
        )
    }

    // MARK: - True / false

    /// `trueFalse` arrives with either answer shape, so branch on the answer, not the kind:
    /// `Answer.boolean` (plain True/False) or `Answer.choice` with three option ids, which is how
    /// the IELTS content spells True/False/Not Given and Yes/No/Not Given.
    private func checkBoolean(_ exercise: Exercise, response: UserResponse) -> ExerciseResult {
        switch exercise.answer.values {
        case .boolean(let expected):
            // A learner may still answer a boolean-keyed exercise by tapping an option id.
            guard let answered = Self.boolAnswer(response) else {
                return booleanResult(exercise, isCorrect: false)
            }
            return booleanResult(exercise, isCorrect: answered == expected)
        case .choice:
            // ...and a choice-keyed exercise may be answered with two buttons. Map the flag back
            // onto the id it stands for before grading as a choice.
            if let flag = response.asBoolean, let id = Self.id(for: flag, among: expectedChoice(exercise)) {
                return checkChoice(exercise, response: .choice([id]), allowPartial: false)
            }
            return checkChoice(exercise, response: response, allowPartial: false)
        default:
            let expected = exercise.items.contains { $0.isCorrect == true }
            guard let answered = Self.boolAnswer(response) else {
                return booleanResult(exercise, isCorrect: false)
            }
            return booleanResult(exercise, isCorrect: answered == expected)
        }
    }

    private func booleanResult(_ exercise: Exercise, isCorrect: Bool) -> ExerciseResult {
        ExerciseResult(
            exerciseID: exercise.id,
            isCorrect: isCorrect,
            accuracy: isCorrect ? 1 : 0,
            correctAnswer: exercise.answer,
            explanation: exercise.explanation,
            diffs: [],
            xpAwarded: isCorrect ? exercise.xp : 0
        )
    }

    /// Option ids that mean "true" / "false" in the content, so a three-option IELTS item and a
    /// two-button answer are interchangeable.
    private static let trueIDs: Set<String> = ["true", "yes", "correct", "t", "y"]
    private static let falseIDs: Set<String> = ["false", "no", "incorrect", "f", "n"]

    /// The learner's True/False answer, or `nil` when the response says neither (e.g. "Not Given"
    /// against a boolean answer, which is simply wrong).
    private static func boolAnswer(_ response: UserResponse) -> Bool? {
        if let flag = response.asBoolean { return flag }
        guard let id = response.asChoice?.first else { return nil }
        return flag(for: id)
    }

    private static func flag(for id: String) -> Bool? {
        let key = id.lowercased()
        if trueIDs.contains(key) { return true }
        if falseIDs.contains(key) { return false }
        return nil
    }

    /// The id standing for `flag`, when the answer offers one.
    private static func id(for flag: Bool, among ids: [String]) -> String? {
        let wanted = flag ? trueIDs : falseIDs
        return ids.first { wanted.contains($0.lowercased()) }
    }

    // MARK: - Matching

    /// `Answer.pairs` has two legal shapes (§"Matching answers") and both ship in content:
    ///
    /// 1. **Item-based** — `items` is non-empty and carries `matchKey`s; the answer maps
    ///    `item.id → item.matchKey` (`adjective-l5-ex3`, `cl-nd-q4`).
    /// 2. **Domain-keyed** — `items` is absent or empty; the keys are map positions, question
    ///    numbers, paragraph letters.
    ///
    /// The learner's map uses the same orientation as the answer, so grading compares the
    /// authored map key-for-key and needs no orientation at all — the "branch on matchKey" rule
    /// lives in ``matchingKeys(for:)``, which the UI needs for its left-hand column.
    /// Note that shipped content also keys some item-based answers by `matchKey` rather than by
    /// `item.id` (`ielts-l-sec2-q1`, `ielts-r-p3-q1`), so nothing here may assume id keys.
    private func checkMatching(_ exercise: Exercise, response: UserResponse) -> ExerciseResult {
        // `Answer.pairs(_:)` is a factory, not a property: read the decoded payload.
        let expected: [String: String]
        if case .pairs(let map) = exercise.answer.values {
            expected = map
        } else {
            expected = [:]
        }
        let chosen = response.asPairs ?? [:]
        var wrong: [WrongPair] = []
        for key in expected.keys.sorted() {
            let want = expected[key] ?? ""
            let got = chosen[key]
            if got != want {
                wrong.append(WrongPair(key: key, user: got, expected: want))
            }
        }
        // A key the learner invented is as wrong as a key they mismatched.
        for key in chosen.keys.sorted() where expected[key] == nil {
            wrong.append(WrongPair(key: key, user: chosen[key], expected: ""))
        }
        let isCorrect = !expected.isEmpty && wrong.isEmpty && chosen.count == expected.count
        let matched = expected.count - wrong.filter { expected[$0.key] != nil }.count
        let accuracy = isCorrect ? 1 : (expected.isEmpty ? 0 : Double(max(0, matched)) / Double(expected.count))
        return ExerciseResult(
            exerciseID: exercise.id,
            isCorrect: isCorrect,
            accuracy: accuracy,
            correctAnswer: exercise.answer,
            explanation: exercise.explanation,
            diffs: [],
            xpAwarded: isCorrect ? exercise.xp : 0,
            wrongPairs: wrong.sorted { $0.key < $1.key }
        )
    }

    /// Display label for every key a matching answer uses, so the UI can render its left column
    /// without knowing which of the two shapes it is looking at.
    ///
    /// The branch is on `matchKey`, never on a guess about the answer's direction: an item's `id`
    /// and its `matchKey` are both registered, because shipped content uses both as the key
    /// vocabulary. Keys with no item (domain-keyed answers, or a key the author left unlabelled)
    /// fall back to the key itself.
    public static func matchingKeys(for exercise: Exercise) -> [String: String] {
        var labels: [String: String] = [:]
        for item in exercise.items {
            let label = item.text ?? item.id
            labels[item.id] = label
            if let matchKey = item.matchKey { labels[matchKey] = label }
        }
        if case .pairs(let values) = exercise.answer.values {
            for key in values.keys where labels[key] == nil { labels[key] = key }
        }
        return labels
    }

    // MARK: - Word order

    private func checkOrder(_ exercise: Exercise, response: UserResponse) -> ExerciseResult {
        let written = response.asOrder ?? []
        let accepted = acceptedOrders(exercise)
        let normalizedWritten = written.map { normalizer.normalize($0) }

        var divergence: Int?
        var isCorrect = false
        for order in accepted {
            let normalizedExpected = order.map { normalizer.normalize($0) }
            let index = firstDivergence(expected: normalizedExpected, written: normalizedWritten)
            if index == nil {
                isCorrect = true
                break
            }
            if divergence == nil || (index ?? 0) < (divergence ?? 0) { divergence = index }
        }
        return orderResult(exercise, isCorrect: isCorrect, divergence: isCorrect ? nil : divergence,
                           written: normalizedWritten, expected: accepted.first?.map { normalizer.normalize($0) } ?? [])
    }

    private func orderResult(
        _ exercise: Exercise,
        isCorrect: Bool,
        divergence: Int?,
        written: [String],
        expected: [String]
    ) -> ExerciseResult {
        let inPlace = zip(expected, written).prefix(while: { $0 == $1 }).count
        let denominator = max(expected.count, written.count)
        let accuracy = isCorrect ? 1 : (denominator == 0 ? 0 : Double(inPlace) / Double(denominator))
        return ExerciseResult(
            exerciseID: exercise.id,
            isCorrect: isCorrect,
            accuracy: accuracy,
            correctAnswer: exercise.answer,
            explanation: exercise.explanation,
            diffs: [],
            xpAwarded: isCorrect ? exercise.xp : 0,
            firstDivergenceIndex: divergence
        )
    }

    private func firstDivergence(expected: [String], written: [String]) -> Int? {
        let shared = min(expected.count, written.count)
        for index in 0 ..< shared where expected[index] != written[index] {
            return index
        }
        return expected.count == written.count ? nil : shared
    }

    // MARK: - Free text

    private func checkText(_ exercise: Exercise, response: UserResponse) -> ExerciseResult {
        let written = response.asText ?? ""
        let (canonical, accepted) = acceptedTexts(exercise)
        let verdict = dictation.evaluate(userInput: written, expected: canonical, accepted: accepted)
        return ExerciseResult(
            exerciseID: exercise.id,
            isCorrect: verdict.isCorrect,
            accuracy: verdict.accuracy,
            correctAnswer: exercise.answer,
            explanation: exercise.explanation,
            diffs: verdict.diffs,
            xpAwarded: verdict.isCorrect ? exercise.xp : 0
        )
    }

    // MARK: - Answer readers

    private func expectedChoice(_ exercise: Exercise) -> [String] {
        if case .choice(let ids) = exercise.answer.values { return ids }
        return exercise.items.filter { $0.isCorrect == true }.map(\.id)
    }

    private func acceptedTexts(_ exercise: Exercise) -> (String, [String]) {
        if case .text(let list) = exercise.answer.values {
            return (list.first ?? exercise.prompt, Array(list.dropFirst()))
        }
        return (exercise.prompt, [])
    }

    /// `Answer.order` holds one ordering. If the content lane ever needs a second accepted
    /// ordering, it can put a space-joined sentence in a `.text` answer; both are read here.
    private func acceptedOrders(_ exercise: Exercise) -> [[String]] {
        var orders: [[String]] = []
        if case .order(let list) = exercise.answer.values, !list.isEmpty { orders.append(list) }
        if case .text(let list) = exercise.answer.values {
            for value in list {
                let tokens = normalizer.tokens(value)
                if !tokens.isEmpty { orders.append(tokens) }
            }
        }
        return orders
    }
}

private extension UserResponse {
    var asText: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    var asChoice: [String]? {
        if case .choice(let value) = self { return value }
        return nil
    }

    var asOrder: [String]? {
        if case .order(let value) = self { return value }
        return nil
    }

    var asPairs: [String: String]? {
        if case .pairs(let value) = self { return value }
        return nil
    }

    var asBoolean: Bool? {
        if case .boolean(let value) = self { return value }
        return nil
    }
}