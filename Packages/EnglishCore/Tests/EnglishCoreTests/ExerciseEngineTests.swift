import Foundation
import Testing

@testable import EnglishCore

private let engine = ExerciseEngine()

// MARK: - Fixtures

private func choiceExercise(kind: ExerciseKind, answer: [String], isCorrectFlags: [Bool]) -> Exercise {
    var exercise = Exercise(
        id: "ex-\(kind.rawValue)",
        kind: kind,
        topicID: "tenses",
        prompt: "Pick the right answer.",
        answer: .choice(answer),
        explanation: "Because.",
        xp: 10
    )
    exercise.items = answer.enumerated().map { index, id in
        ExerciseItem(id: id, text: "Option \(index)", isCorrect: isCorrectFlags[index])
    }
    return exercise
}

// MARK: - Choice kinds

@Test("multipleChoice grades an exact id match")
func multipleChoice() {
    let exercise = choiceExercise(kind: .multipleChoice, answer: ["a", "b", "c"], isCorrectFlags: [false, true, false])
    let good = engine.check(exercise, response: .choice(["b"]))
    #expect(good.isCorrect)
    #expect(good.accuracy == 1)
    #expect(good.xpAwarded == 10)

    let bad = engine.check(exercise, response: .choice(["a"]))
    #expect(!bad.isCorrect)
    #expect(bad.accuracy == 0, "a pure choice question gets no partial credit")
    #expect(bad.xpAwarded == 0)
    #expect(bad.missedChoiceIDs == ["b"])
    #expect(bad.extraChoiceIDs == ["a"])
}

@Test("reading grades like multipleChoice")
func reading() {
    let exercise = choiceExercise(kind: .reading, answer: ["x"], isCorrectFlags: [true])
    #expect(engine.check(exercise, response: .choice(["x"])).isCorrect)
    #expect(!engine.check(exercise, response: .choice(["y"])).isCorrect)
}

@Test("listening grades like multipleChoice")
func listening() {
    let exercise = choiceExercise(kind: .listening, answer: ["x"], isCorrectFlags: [true])
    #expect(engine.check(exercise, response: .choice(["x"])).isCorrect)
    #expect(!engine.check(exercise, response: .choice(["z"])).isCorrect)
}

@Test("listeningComprehension grades like multipleChoice")
func listeningComprehension() {
    let exercise = choiceExercise(kind: .listeningComprehension, answer: ["x"], isCorrectFlags: [true])
    #expect(engine.check(exercise, response: .choice(["x"])).isCorrect)
    #expect(!engine.check(exercise, response: .choice([])).isCorrect)
}

@Test("multiSelect needs an exact set, and a partial selection is not a pass")
func multiSelect() {
    let exercise = choiceExercise(kind: .multiSelect, answer: ["a", "c"], isCorrectFlags: [true, false, true])

    let partial = engine.check(exercise, response: .choice(["a"]))
    #expect(!partial.isCorrect, "one of two correct options is not a pass")
    #expect(partial.accuracy == 0.5)
    #expect(partial.xpAwarded == 0)
    #expect(partial.missedChoiceIDs == ["c"])
    #expect(partial.extraChoiceIDs.isEmpty)

    let wrong = engine.check(exercise, response: .choice(["a", "b"]))
    #expect(!wrong.isCorrect)
    #expect(wrong.missedChoiceIDs == ["c"])
    #expect(wrong.extraChoiceIDs == ["b"])

    #expect(engine.check(exercise, response: .choice(["c", "a"])).isCorrect, "order-independent")
}

// MARK: - True / false

@Test("trueFalse compares the boolean answer")
func trueFalse() {
    let exercise = Exercise(
        id: "ex-tf", kind: .trueFalse, topicID: "tenses",
        prompt: "The present simple uses -s.", answer: .boolean(true), xp: 5
    )
    #expect(engine.check(exercise, response: .boolean(true)).isCorrect)
    let wrong = engine.check(exercise, response: .boolean(false))
    #expect(!wrong.isCorrect)
    #expect(wrong.accuracy == 0)
    #expect(wrong.xpAwarded == 0)
}

@Test("multipleChoice with three options grades the same as four")
func threeOptionMultipleChoice() {
    let exercise = choiceExercise(kind: .multipleChoice, answer: ["a", "b", "c"], isCorrectFlags: [false, true, false])
    #expect(exercise.items.count == 3)
    #expect(engine.check(exercise, response: .choice(["b"])).isCorrect)
    let wrong = engine.check(exercise, response: .choice(["a"]))
    #expect(!wrong.isCorrect)
    #expect(wrong.missedChoiceIDs == ["b"])
    #expect(wrong.extraChoiceIDs == ["a"])
    #expect(!engine.check(exercise, response: .choice(["a", "b"])).isCorrect, "one pick only")
}

@Test("trueFalse answers a choice-shaped True/False/Not Given item by option id")
func trueFalseChoiceShaped() {
    let exercise = Exercise(
        id: "ielts-r-p1-q1", kind: .trueFalse, topicID: "ielts",
        prompt: "The museum opens at 9.", instruction: "True, False or Not Given?",
        items: [
            ExerciseItem(id: "true", text: "True", isCorrect: false),
            ExerciseItem(id: "false", text: "False", isCorrect: false),
            ExerciseItem(id: "ng", text: "Not Given", isCorrect: true),
        ],
        answer: .choice(["ng"]),
        xp: 5
    )
    let right = engine.check(exercise, response: .choice(["ng"]))
    #expect(right.isCorrect)
    #expect(right.accuracy == 1)
    #expect(right.xpAwarded == 5)
    #expect(right.correctAnswer.values == .choice(["ng"]))

    let wrong = engine.check(exercise, response: .choice(["true"]))
    #expect(!wrong.isCorrect)
    #expect(wrong.accuracy == 0)
    #expect(wrong.missedChoiceIDs == ["ng"])
    #expect(wrong.extraChoiceIDs == ["true"])

    #expect(!engine.check(exercise, response: .choice(["ng", "true"])).isCorrect, "exact set, not a subset")
    #expect(!engine.check(exercise, response: .choice([])).isCorrect)
}

@Test("trueFalse answers a choice-shaped Yes/No/Not Given item")
func yesNoNotGiven() {
    let exercise = Exercise(
        id: "ielts-r-p2-q1", kind: .trueFalse, topicID: "ielts",
        prompt: "The course lasts one year.",
        items: [
            ExerciseItem(id: "yes", text: "Yes", isCorrect: true),
            ExerciseItem(id: "no", text: "No", isCorrect: false),
            ExerciseItem(id: "ng", text: "Not Given", isCorrect: false),
        ],
        answer: .choice(["yes"]),
        xp: 5
    )
    #expect(engine.check(exercise, response: .choice(["yes"])).isCorrect)
    #expect(!engine.check(exercise, response: .choice(["no"])).isCorrect)
    #expect(!engine.check(exercise, response: .choice(["ng"])).isCorrect)
}

@Test("the two answer shapes of trueFalse accept each other's response")
func trueFalseShapesAreInterchangeable() {
    let booleanKeyed = Exercise(
        id: "ex-tf-bool", kind: .trueFalse, topicID: "tenses",
        prompt: "He goes to school.", answer: .boolean(true), xp: 5
    )
    // A learner tapping a "True" option is understood even though the answer is a boolean.
    #expect(engine.check(booleanKeyed, response: .choice(["true"])).isCorrect)
    #expect(!engine.check(booleanKeyed, response: .choice(["false"])).isCorrect)
    // "Not Given" is not an answer to a boolean question; it must not pass as `false`.
    #expect(!engine.check(booleanKeyed, response: .choice(["ng"])).isCorrect)
    #expect(!engine.check(booleanKeyed, response: .text("true")).isCorrect, "a non-answer is not true")
    #expect(engine.check(booleanKeyed, response: .boolean(true)).isCorrect)

    let choiceKeyed = Exercise(
        id: "ex-tf-choice", kind: .trueFalse, topicID: "ielts",
        prompt: "He goes to school.",
        items: [
            ExerciseItem(id: "true", text: "True", isCorrect: false),
            ExerciseItem(id: "false", text: "False", isCorrect: true),
        ],
        answer: .choice(["false"]),
        xp: 5
    )
    // Two-button UI against three-option content: the flag maps onto the right id.
    #expect(engine.check(choiceKeyed, response: .boolean(false)).isCorrect)
    #expect(!engine.check(choiceKeyed, response: .boolean(true)).isCorrect)
}

// MARK: - Text kinds

@Test("fillInTheBlank accepts any listed value")
func fillInTheBlank() {
    let exercise = Exercise(
        id: "ex-blank", kind: .fillInTheBlank, topicID: "tenses",
        prompt: "He ___ (go) to school.", answer: .text(["goes", "go"]), xp: 10
    )
    #expect(engine.check(exercise, response: .text("Goes.")).isCorrect)
    #expect(engine.check(exercise, response: .text("go")).isCorrect)
    let wrong = engine.check(exercise, response: .text("going"))
    #expect(!wrong.isCorrect)
    #expect(!wrong.diffs.isEmpty, "text kinds get token-level feedback")
    #expect(wrong.accuracy < 1)
}

@Test("typeTheAnswer compares normalised text")
func typeTheAnswer() {
    let exercise = Exercise(
        id: "ex-type", kind: .typeTheAnswer, topicID: "verb",
        prompt: "Type the past of go.", answer: .text(["went"]), xp: 10
    )
    #expect(engine.check(exercise, response: .text(" went ")).isCorrect)
    #expect(!engine.check(exercise, response: .text("goed")).isCorrect)
}

@Test("dictation routes through the dictation engine for token feedback")
func dictationExercise() {
    let exercise = Exercise(
        id: "ex-dict", kind: .dictation, topicID: "tenses",
        prompt: "Write what you hear.", answer: .text(["The boy is playing football.", "The boys are playing football."]),
        xp: 15
    )
    #expect(engine.check(exercise, response: .text("the boy is playing football")).isCorrect)
    #expect(engine.checkDictation(exercise, userInput: "The boys are playing football.").isCorrect)

    let wrong = engine.checkDictation(exercise, userInput: "The boy play football.")
    #expect(!wrong.isCorrect)
    #expect(wrong.diffs.contains { $0.kind == .substituted })
    #expect(wrong.xpAwarded == 0)
    #expect(wrong.correctAnswer.values == .text(["The boy is playing football.", "The boys are playing football."]))
}

@Test("sentenceCompletion accepts a listed word")
func sentenceCompletion() {
    let exercise = Exercise(
        id: "ex-sc", kind: .sentenceCompletion, topicID: "tenses",
        prompt: "She ___ to school every day.", answer: .text(["walks"]), xp: 10
    )
    #expect(engine.check(exercise, response: .text("Walks")).isCorrect)
    #expect(!engine.check(exercise, response: .text("walk")).isCorrect)
}

@Test("errorCorrection compares the corrected sentence")
func errorCorrection() {
    let exercise = Exercise(
        id: "ex-ec", kind: .errorCorrection, topicID: "tenses",
        prompt: "She go to school.", answer: .text(["She goes to school."]), xp: 10
    )
    #expect(engine.check(exercise, response: .text("she goes to school")).isCorrect)
    let wrong = engine.check(exercise, response: .text("She go to school."))
    #expect(!wrong.isCorrect)
    #expect(wrong.diffs.contains { $0.expected == "goes" })
}

@Test("wordFormation compares the target form")
func wordFormation() {
    let exercise = Exercise(
        id: "ex-wf", kind: .wordFormation, topicID: "word-formation",
        prompt: "achieve (noun)", answer: .text(["achievement"]), xp: 10
    )
    #expect(engine.check(exercise, response: .text("Achievement")).isCorrect)
    #expect(!engine.check(exercise, response: .text("achieve")).isCorrect)
}

@Test("translation compares normalised text")
func translation() {
    let exercise = Exercise(
        id: "ex-tr", kind: .translation, topicID: "tenses",
        prompt: "Cậu bé đang chơi bóng đá.", answer: .text(["The boy is playing football."]), xp: 15
    )
    #expect(engine.check(exercise, response: .text("the boy is playing football.")).isCorrect)
    #expect(!engine.check(exercise, response: .text("The boy is playing")).isCorrect)
}

@Test("grammarCorrection compares the corrected sentence")
func grammarCorrection() {
    let exercise = Exercise(
        id: "ex-gc", kind: .grammarCorrection, topicID: "passive-voice",
        prompt: "The window was broke.", answer: .text(["The window was broken."]), xp: 10
    )
    #expect(engine.check(exercise, response: .text("The window was broken")).isCorrect)
    #expect(!engine.check(exercise, response: .text("The window was broke")).isCorrect)
}

// MARK: - Matching

@Test("matching surfaces the pairs the learner got wrong")
func matching() {
    let exercise = Exercise(
        id: "ex-match", kind: .matching, topicID: "noun",
        prompt: "Match the word to its article.",
        answer: .pairs(["a": "an", "b": "a", "c": "the"]),
        xp: 10
    )
    let perfect = engine.check(exercise, response: .pairs(["a": "an", "b": "a", "c": "the"]))
    #expect(perfect.isCorrect)
    #expect(perfect.wrongPairs.isEmpty)

    let partial = engine.check(exercise, response: .pairs(["a": "an", "b": "the", "c": "the"]))
    #expect(!partial.isCorrect)
    #expect(partial.wrongPairs.count == 1)
    #expect(partial.wrongPairs[0].key == "b")
    #expect(partial.wrongPairs[0].user == "the")
    #expect(partial.wrongPairs[0].expected == "a")
    #expect(partial.accuracy == 2.0 / 3.0)

    let invented = engine.check(exercise, response: .pairs(["a": "an", "b": "a", "c": "the", "d": "an"]))
    #expect(!invented.isCorrect)
    #expect(invented.wrongPairs.contains { $0.key == "d" })
}

@Test("matching, item-based shape: the answer maps item.id to item.matchKey")
func matchingItemBased() {
    // Shape as shipped in topics/adjective.json (adjective-l5-ex3).
    let exercise = Exercise(
        id: "adjective-l5-ex3", kind: .matching, topicID: "adjective",
        prompt: "Match the adjective to the preposition.",
        items: [
            ExerciseItem(id: "m1", text: "proud", matchKey: "of"),
            ExerciseItem(id: "m2", text: "dependent", matchKey: "on"),
            ExerciseItem(id: "m3", text: "capable", matchKey: "of"),
            ExerciseItem(id: "m4", text: "used", matchKey: "to"),
        ],
        answer: .pairs(["m1": "of", "m2": "on", "m3": "of", "m4": "to"]),
        xp: 10
    )
    let perfect = engine.check(
        exercise,
        response: .pairs(["m1": "of", "m2": "on", "m3": "of", "m4": "to"])
    )
    #expect(perfect.isCorrect)
    #expect(perfect.accuracy == 1)
    #expect(perfect.xpAwarded == 10)

    // Repeating a matchKey is legal here; a mismatched one is not, and the UI needs to know which.
    let partial = engine.check(
        exercise,
        response: .pairs(["m1": "of", "m2": "of", "m3": "of", "m4": "to"])
    )
    #expect(!partial.isCorrect)
    #expect(partial.wrongPairs.count == 1)
    #expect(partial.wrongPairs[0] == WrongPair(key: "m2", user: "of", expected: "on"))
    #expect(partial.accuracy == 3.0 / 4.0)
}

@Test("matching, domain-keyed shape: no items, labels compared literally")
func matchingDomainKeyed() {
    // Shape as shipped in ielts-listening-reading.json (ielts-l-sec2-q1, with items omitted).
    let exercise = Exercise(
        id: "ielts-l-sec2-q1", kind: .matching, topicID: "ielts",
        prompt: "Match the map positions to the numbered places.",
        answer: .pairs(["A": "1", "B": "2", "C": "3", "D": "4"]),
        xp: 10
    )
    #expect(engine.check(exercise, response: .pairs(["A": "1", "B": "2", "C": "3", "D": "4"])).isCorrect)
    #expect(engine.check(exercise, response: .pairs(["D": "4", "C": "3", "B": "2", "A": "1"])).isCorrect,
            "a map has no order; only the pairing matters")

    let swapped = engine.check(exercise, response: .pairs(["A": "2", "B": "1", "C": "3", "D": "4"]))
    #expect(!swapped.isCorrect)
    #expect(swapped.wrongPairs.map(\.key) == ["A", "B"])
    #expect(swapped.wrongPairs.map(\.expected) == ["1", "2"])
    #expect(swapped.accuracy == 2.0 / 4.0)

    // A missing key is not a partial pass.
    #expect(!engine.check(exercise, response: .pairs(["A": "1", "B": "2", "C": "3"])).isCorrect)
    #expect(!engine.check(exercise, response: .pairs([:])).isCorrect)
}

@Test("matching grades an answer keyed by matchKey, as several shipped IELTS items are")
func matchingKeyedByMatchKey() {
    // ielts-r-p3-q1: items carry matchKey, but the answer is keyed by the matchKey, not the id.
    let exercise = Exercise(
        id: "ielts-r-p3-q1", kind: .matching, topicID: "ielts",
        prompt: "Match the statements to the findings.",
        items: [
            ExerciseItem(id: "mi1", text: "Used for years without data.", matchKey: "1"),
            ExerciseItem(id: "mi2", text: "Losing concentration, not saving time.", matchKey: "2"),
        ],
        answer: .pairs(["1": "A", "2": "B"]),
        xp: 10
    )
    #expect(engine.check(exercise, response: .pairs(["1": "A", "2": "B"])).isCorrect)
    #expect(!engine.check(exercise, response: .pairs(["1": "B", "2": "A"])).isCorrect)
    // The id-keyed reading of the same answer is a different, wrong map.
    #expect(!engine.check(exercise, response: .pairs(["mi1": "1", "mi2": "2"])).isCorrect)
}

@Test("matchingKeys labels every key of both shapes for the UI")
func matchingKeyLabels() {
    let itemBased = Exercise(
        id: "adjective-l5-ex3", kind: .matching, topicID: "adjective",
        prompt: "Match.", items: [ExerciseItem(id: "m1", text: "proud", matchKey: "of")],
        answer: .pairs(["m1": "of"]), xp: 10
    )
    let labels = ExerciseEngine.matchingKeys(for: itemBased)
    #expect(labels["m1"] == "proud", "item id resolves to the item's text")
    #expect(labels["of"] == "proud", "matchKey resolves to the same item's text")

    let matchKeyed = Exercise(
        id: "ielts-r-p3-q1", kind: .matching, topicID: "ielts",
        prompt: "Match.", items: [ExerciseItem(id: "mi1", text: "Used for years.", matchKey: "1")],
        answer: .pairs(["1": "A"]), xp: 10
    )
    #expect(ExerciseEngine.matchingKeys(for: matchKeyed)["1"] == "Used for years.")

    let domainKeyed = Exercise(
        id: "ielts-l-sec2-q1", kind: .matching, topicID: "ielts",
        prompt: "Match.", answer: .pairs(["A": "1", "B": "2"]), xp: 10
    )
    let plain = ExerciseEngine.matchingKeys(for: domainKeyed)
    #expect(plain["A"] == "A", "no item, so the key stands for itself")
    #expect(plain["B"] == "B")
}

// MARK: - Rearrange

@Test("rearrangeWords reports the first divergence index and keeps the learner's words")
func rearrangeWords() {
    let exercise = Exercise(
        id: "ex-order", kind: .rearrangeWords, topicID: "tenses",
        prompt: "Put the words in order.",
        answer: .order(["I", "go", "to", "school", "in", "the", "morning"]),
        xp: 10
    )
    #expect(engine.check(exercise, response: .order(["I", "go", "to", "school", "in", "the", "morning"])).isCorrect)

    let swapped = engine.check(exercise, response: .order(["I", "go", "in", "school", "to", "the", "morning"]))
    #expect(!swapped.isCorrect)
    #expect(swapped.firstDivergenceIndex == 2, "the learner put 'in' where 'to' belongs")
    #expect(swapped.xpAwarded == 0)

    let short = engine.check(exercise, response: .order(["I", "go", "to", "school"]))
    #expect(!short.isCorrect)
    #expect(short.firstDivergenceIndex == 4, "diverges where the learner ran out of words")
}

@Test("a wrong response for a text kind keeps the exercise id and explanation")
func resultCarriesExerciseMetadata() {
    let exercise = Exercise(
        id: "ex-meta", kind: .typeTheAnswer, topicID: "verb",
        prompt: "Past of eat?", answer: .text(["ate"]), explanation: "Irregular.", xp: 7
    )
    let result = engine.check(exercise, response: .text("eated"))
    #expect(result.exerciseID == "ex-meta")
    #expect(result.explanation == "Irregular.")
    #expect(result.diffs.count == 1)
}

@Test("result and diff types stay constructible with the contract labels, in order")
func resultTypesStayConstructible() {
    // EnglishStore and the app target build these by hand; the seven-argument form must keep working.
    let diff = TokenDiff(id: 0, kind: .missing, index: 2, user: nil, expected: "is")
    let result = ExerciseResult(
        exerciseID: "ex-1",
        isCorrect: false,
        accuracy: 0.5,
        correctAnswer: .text(["goes"]),
        explanation: "Because.",
        diffs: [diff],
        xpAwarded: 0
    )
    #expect(result.exerciseID == "ex-1")
    #expect(result.diffs == [diff])
    #expect(result.wrongPairs.isEmpty)
    #expect(result.firstDivergenceIndex == nil)

    let short = TokenDiff(id: 1, kind: .extra, index: 3, user: "a")
    #expect(short.expected == nil)
    #expect(short.index == 3)

    let full = DictationResult(
        isCorrect: true, accuracy: 1, diffs: [], firstErrorIndex: nil,
        expected: "Hi.", firstErrorSummary: nil
    )
    #expect(full.isCorrect)
    #expect(full.expected == "Hi.")
    let bare = DictationResult(isCorrect: false, accuracy: 0, diffs: [short])
    #expect(bare.firstErrorSummary == nil)
    #expect(bare.diffs == [short])
}

@Test("a response of the wrong shape is wrong, not a crash")
func mismatchedResponseShapeIsWrong() {
    let exercise = Exercise(
        id: "ex-shape", kind: .trueFalse, topicID: "verb",
        prompt: "Statement", answer: .boolean(true), xp: 5
    )
    let result = engine.check(exercise, response: .text("true"))
    #expect(!result.isCorrect)
    #expect(result.accuracy == 0)
}