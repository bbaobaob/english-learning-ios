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
    let wrong = engine.check(exercise, response: .text("She go to school.")
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