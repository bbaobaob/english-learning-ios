import Foundation
import Testing

@testable import EnglishCore

// MARK: - Fixtures

private func exercise(id: String, answer: String = "goes") -> Exercise {
    Exercise(
        id: id, kind: .fillInTheBlank, topicID: "tenses",
        prompt: "He ___ (go) to school.", answer: .text([answer]), xp: 10
    )
}

private func dictationItem(_ id: String, expected: String, accepted: [String] = [], xp: Int = 15) -> DictationItem {
    DictationItem(
        id: id,
        audio: AudioClip(id: "clip-\(id)", kind: .speech, text: expected),
        acceptedAnswers: accepted,
        xp: xp
    )
}

private func theory(_ id: String) -> SessionItem {
    .theory(.theory(TheoryStep(id: id, heading: "Heading", body: "Body")))
}

// MARK: - Ordering

@Test("the session walks items in order")
@MainActor
func sessionWalksItemsInOrder() {
    let items: [SessionItem] = [theory("step-1"), .exercise(exercise(id: "ex-1")), .summary(takeaways: ["One thing"])]
    let session = LearnSession(items: items)
    #expect(session.index == 0)
    #expect(session.current?.id == items[0].id)
    #expect(session.next())
    #expect(session.index == 1)
    #expect(session.current?.id == items[1].id)
    #expect(session.next())
    #expect(session.index == 2)
    #expect(!session.isFinished)
    #expect(!session.next(), "next() returns false once the last item is left")
    #expect(session.isFinished)
    #expect(session.current == nil)
}

@Test("submitting a non-graded step records nothing")
@MainActor
func nonGradedStepRecordsNothing() {
    let session = LearnSession(items: [theory("step-1")])
    let result = session.submit(.text("anything"))
    #expect(result.xpAwarded == 0)
    #expect(session.results.isEmpty)
}

// MARK: - Grading through the session

@Test("dictation items are graded against the clip text and accepted answers")
@MainActor
func dictationItemIsGraded() {
    let session = LearnSession(items: [
        .dictation(dictationItem("d-1", expected: "The boy is playing football.", accepted: ["The boys are playing football."])),
        .exercise(exercise(id: "ex-1")),
    ])
    #expect(session.submitDictation("the boy is playing football").isCorrect)
    #expect(session.next())

    let wrong = session.submit(.text("go"))
    #expect(!wrong.isCorrect)
    #expect(wrong.exerciseID == "ex-1")
    #expect(wrong.explanation == "")
    #expect(wrong.diffs.count == 1, "a one-word answer against a one-word answer is one substitution")
    #expect(wrong.diffs[0].kind == .substituted)
}

@Test("a wrong dictation answer is still graded on its own")
@MainActor
func dictationAcceptedAnswersWork() {
    let session = LearnSession(items: [
        .dictation(dictationItem("d-1", expected: "The boy is playing football.", accepted: ["The boys are playing football."]))
    ])
    #expect(session.submitDictation("The boys are playing football.").isCorrect)
    #expect(session.isFinished, "the last item is finished as soon as it is answered")
}

// MARK: - onComplete

@Test("onComplete fires exactly once, when the last item is finished")
@MainActor
func onCompleteFiresOnce() {
    final class Counter: @unchecked Sendable { var calls = 0; var last: SessionOutcome? }
    let counter = Counter()
    let session = LearnSession(
        items: [.exercise(exercise(id: "ex-1")), theory("step-1")],
        onComplete: { outcome in
            counter.calls += 1
            counter.last = outcome
        }
    )
    #expect(counter.calls == 0)
    _ = session.submit(.text("goes"))
    #expect(counter.calls == 0, "not the last item yet")

    #expect(session.next())
    #expect(counter.calls == 0, "a read-only step does not end the session")
    #expect(!session.next())
    #expect(counter.calls == 1)
    #expect(counter.last?.wrongIDs.isEmpty == true)
    #expect(counter.last?.xpEarned == 10)

    // Further next() calls must not fire it again.
    _ = session.next()
    #expect(counter.calls == 1)
}

@Test("an empty session is finished from the start")
@MainActor
func emptySessionIsFinished() {
    let session = LearnSession(items: [])
    #expect(session.isFinished)
    #expect(session.current == nil)
    #expect(!session.next())
    #expect(session.results.isEmpty)
    #expect(session.outcome == SessionOutcome(accuracy: 0, xpEarned: 0, wrongIDs: []))
}

// MARK: - retry

@Test("retry clears only the current result")
@MainActor
func retryKeepsEarlierResults() {
    let session = LearnSession(items: [
        .exercise(exercise(id: "ex-1", answer: "goes")),
        .exercise(exercise(id: "ex-2", answer: "walks")),
    ])
    _ = session.submit(.text("goes"))
    #expect(session.next())
    let second = session.submit(.text("run"))
    #expect(!second.isCorrect)
    #expect(session.results.count == 2)
    #expect(session.outcome.xpEarned == 10)

    session.retry()
    #expect(session.results.count == 1)
    #expect(session.results[0].exerciseID == "ex-1")
    #expect(session.outcome.xpEarned == 10, "earlier XP survives the retry")

    let again = session.submit(.text("walks"))
    #expect(again.isCorrect)
    #expect(session.results.count == 2, "re-answering replaces rather than stacks")
    #expect(session.outcome.wrongIDs.isEmpty)
    #expect(session.outcome.xpEarned == 20)
}

@Test("retry on an unanswered item does nothing")
@MainActor
func retryWithoutAnswerIsSafe() {
    let session = LearnSession(items: [.exercise(exercise(id: "ex-1"))])
    session.retry()
    #expect(session.results.isEmpty)
}

// MARK: - outcome

@Test("outcome totals accuracy, XP and wrong ids")
@MainActor
func outcomeTotals() {
    let session = LearnSession(items: [
        .exercise(exercise(id: "ex-1", answer: "goes")),
        .exercise(exercise(id: "ex-2", answer: "walks")),
        .exercise(exercise(id: "ex-3", answer: "reads")),
    ])
    _ = session.submit(.text("goes"))     // correct
    _ = session.next()
    _ = session.submit(.text("run"))      // wrong
    _ = session.next()
    _ = session.submit(.text("reads"))    // correct

    let outcome = session.outcome
    #expect(outcome.xpEarned == 20)
    #expect(outcome.wrongIDs == ["ex-2"])
    #expect(outcome.accuracy == (1.0 + 0.0 + 1.0) / 3.0)
}

// MARK: - Identity

@Test("session item ids are stable and namespaced")
func sessionItemIDsAreStable() {
    #expect(SessionItem.exercise(exercise(id: "ex-1")).id == "exercise:ex-1")
    #expect(SessionItem.dictation(dictationItem("d-1", expected: "Hi.")).id == "dictation:d-1")
    #expect(theory("step-9").id == "theory:step-9")
    #expect(SessionItem.examples([Example(id: "e-1", en: "A.", vi: "A.")]).id == "examples:e-1")
    #expect(SessionItem.summary(takeaways: ["First"]).id == "summary:First")
    #expect(SessionItem.video(VideoClip(id: "v-1")).id == "video:v-1")
    #expect(SessionItem.audio(AudioClip(id: "a-1")).id == "audio:a-1")
    #expect(theory("step-9").id != theory("step-10").id)
}

@Test("only exercise and dictation items are graded")
func gradedItems() {
    #expect(SessionItem.exercise(exercise(id: "ex-1")).isGraded)
    #expect(SessionItem.dictation(dictationItem("d-1", expected: "Hi.")).isGraded)
    #expect(!theory("step-1").isGraded)
    #expect(!SessionItem.summary(takeaways: []).isGraded)
    #expect(SessionItem.exercise(exercise(id: "ex-1")).asExercise?.id == "ex-1")
    #expect(SessionItem.dictation(dictationItem("d-1", expected: "Hi.")).asDictationItem?.id == "d-1")
}