import Foundation
import Testing

@testable import EnglishCore

private let engine = DictationEngine()

// MARK: - §2 required behaviours

@Test("case and punctuation variants of the canonical sentence are correct")
func caseAndPunctuationVariantsAreCorrect() {
    let expected = "The boy is playing football."
    for variant in [
        "the boy is playing football",
        "The boy is playing football",
        "THE BOY IS PLAYING FOOTBALL",
        "  the   boy is playing football.  ",
        "The boy is playing football!",
    ] {
        let result = engine.evaluate(userInput: variant, expected: expected)
        #expect(result.isCorrect, "variant should be accepted: \(variant)")
        #expect(result.accuracy == 1)
        #expect(result.diffs.isEmpty)
        #expect(result.firstErrorSummary == nil)
    }
}

@Test("whitespace-only differences are correct")
func whitespaceOnlyDifferencesAreCorrect() {
    let result = engine.evaluate(userInput: "\tThe boy\nis   playing  football .  ", expected: "The boy is playing football.")
    #expect(result.isCorrect)
    #expect(result.accuracy == 1)
}

@Test("play instead of playing is incorrect with a substitution")
func playInsteadOfPlayingIsIncorrect() {
    let result = engine.evaluate(userInput: "The boy play football.", expected: "The boy is playing football.")
    #expect(!result.isCorrect)
    let substitution = result.diffs.first { $0.kind == .substituted }
    #expect(substitution?.user == "play")
    #expect(substitution?.expected == "playing")
}

@Test("is play instead of is playing is incorrect and the summary says so")
func isPlayInsteadOfIsPlayingIsIncorrect() {
    let result = engine.evaluate(userInput: "The boy is play football.", expected: "The boy is playing football.")
    #expect(!result.isCorrect)
    let summary = try! #require(result.firstErrorSummary)
    #expect(summary.contains("is playing"), "got: \(summary)")
    #expect(summary.contains("→"))
}

@Test("a missing word produces a missing diff")
func missingWordProducesMissingDiff() {
    let result = engine.evaluate(userInput: "The boy football.", expected: "The boy is playing football.")
    #expect(!result.isCorrect)
    #expect(result.diffs.contains { $0.kind == .missing })
    #expect(result.diffs.contains { $0.expected == "is" })
    #expect(result.accuracy < 1)
}

@Test("an extra word produces an extra diff")
func extraWordProducesExtraDiff() {
    let result = engine.evaluate(userInput: "The boy is playing a football.", expected: "The boy is playing football.")
    #expect(!result.isCorrect)
    #expect(result.diffs.contains { $0.kind == .extra && $0.user == "a" })
}

@Test("accuracy is matched words over the longer side")
func accuracyIsWordLevel() {
    // 4 of 5 words matched, and both sides are 5 words long.
    let result = engine.evaluate(userInput: "the boy is playing ball", expected: "the boy is playing football")
    #expect(!result.isCorrect)
    #expect(result.accuracy == 4.0 / 5.0)
    // The longer side is what the ratio uses.
    let longer = engine.evaluate(userInput: "the boy is playing a football", expected: "the boy is playing football")
    #expect(longer.accuracy == 5.0 / 6.0)
}

// MARK: - §2 step 7

@Test("an accepted alternative is correct even when the canonical sentence was not written")
func acceptedAlternativeIsCorrect() {
    let result = engine.evaluate(
        userInput: "The boys are playing football",
        expected: "The boy is playing football.",
        accepted: ["The boys are playing football."]
    )
    #expect(result.isCorrect)
    #expect(result.accuracy == 1)
    #expect(result.diffs.isEmpty)
    #expect(result.expected == "The boy is playing football.")
}

// MARK: - Contractions, diacritics, edges

@Test("contractions keep their apostrophe")
func contractionsKeepTheirApostrophe() {
    #expect(AnswerNormalizer().normalize("Don't stop.") == "don't stop")
    let result = engine.evaluate(userInput: "Don't stop.", expected: "dont stop")
    #expect(!result.isCorrect, "dropping the apostrophe would make these the same word")
    #expect(result.diffs.contains { $0.kind == .substituted && $0.user == "don't" })

    let curly = engine.evaluate(userInput: "Don’t stop.", expected: "Don't stop.")
    #expect(curly.isCorrect)
}

@Test("diacritics fold to their base letters")
func diacriticsFold() {
    let normalizer = AnswerNormalizer()
    #expect(normalizer.isEquivalent("Café", "cafe"))
    #expect(normalizer.isEquivalent("café", "CAFÉ"))
    #expect(normalizer.normalize("crème brûlée") == "creme brulee")
    let result = engine.evaluate(userInput: "Cafe au lait", expected: "Café au lait.")
    #expect(result.isCorrect)
}

@Test("empty input is incorrect with everything missing")
func emptyInputIsIncorrect() {
    let result = engine.evaluate(userInput: "   ", expected: "The boy is playing football.")
    #expect(!result.isCorrect)
    #expect(result.accuracy == 0)
    #expect(result.diffs.allSatisfy { $0.kind == .missing })
    #expect(result.firstErrorIndex == 0)
}

@Test("empty input against an empty sentence is correct")
func emptyInputAgainstEmptySentenceIsCorrect() {
    let result = engine.evaluate(userInput: "", expected: "")
    #expect(result.isCorrect)
    #expect(result.accuracy == 1)
}

@Test("a single-token answer compares token by token")
func singleTokenAnswer() {
    #expect(engine.evaluate(userInput: "goes", expected: "goes").isCorrect)
    let result = engine.evaluate(userInput: "go", expected: "goes")
    #expect(!result.isCorrect)
    #expect(result.diffs.count == 1)
    #expect(result.diffs[0].kind == .substituted)
    #expect(result.diffs[0].expected == "goes")
    #expect(result.diffs[0].user == "go")
    #expect(result.firstErrorSummary == "“go” → should be “goes”")
}

@Test("a wholly different sentence reports substitutions, not one long missing run")
func whollyDifferentSentenceReportsSubstitutions() {
    let result = engine.evaluate(userInput: "a b", expected: "x y")
    #expect(!result.isCorrect)
    #expect(result.diffs.count == 2)
    #expect(result.diffs.allSatisfy { $0.kind == .substituted })
}

@Test("tokenizer collapses whitespace and drops punctuation")
func tokenizerCollapsesWhitespace() {
    let normalizer = AnswerNormalizer()
    #expect(normalizer.tokens("The boy is playing football.") == ["the", "boy", "is", "playing", "football"])
    #expect(normalizer.tokens("  ") == [])
}