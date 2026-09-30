import Foundation

/// Word-level verdict for a dictated sentence.
public struct DictationResult: Sendable, Equatable {
    /// Whether the sentence was accepted (exact, or one of the accepted alternatives).
    public let isCorrect: Bool
    /// `0...1`, matched words over `max(expected, written)`.
    public let accuracy: Double
    /// Word-level disagreements, in reading order.
    public let diffs: [TokenDiff]
    /// Index of the first divergent word, for placing the caret in the learner's input.
    public let firstErrorIndex: Int?
    /// The canonical sentence as authored, unnormalised.
    public let expected: String
    /// Human-readable first mistake, e.g. `“play” → should be “is playing”`. `nil` when correct.
    public var firstErrorSummary: String?
}

/// Grades dictated sentences against a canonical sentence, per ARCHITECTURE.md §2 step 1–7.
public struct DictationEngine: Sendable {
    private let normalizer: AnswerNormalizer

    public init(normalizer: AnswerNormalizer = AnswerNormalizer()) {
        self.normalizer = normalizer
    }

    /// Grades `userInput` against `expected`, or against any of `accepted` alternatives.
    public func evaluate(userInput: String, expected: String, accepted: [String] = []) -> DictationResult {
        let expectedTokens = normalizer.tokens(expected)
        let userTokens = normalizer.tokens(userInput)

        // Step 7 is checked first: an accepted alternative wins outright and reports no diffs,
        // otherwise the learner would be shown errors for writing a sentence we told them was fine.
        if accepted.contains(where: { normalizer.isEquivalent(userInput, $0) }) {
            return DictationResult(
                isCorrect: true, accuracy: 1, diffs: [], firstErrorIndex: nil,
                expected: expected, firstErrorSummary: nil
            )
        }

        // Steps 3–4.
        let ops = align(expected: expectedTokens, user: userTokens)
        let diffs = diffs(from: ops, expected: expectedTokens, user: userTokens)
        let matched = ops.filter { if case .match = $0 { return true } else { return false } }.count
        // Step 5. Both sides empty means the author wrote nothing gradeable; treat as no error.
        let denominator = max(expectedTokens.count, userTokens.count)
        let accuracy = denominator == 0 ? 1.0 : Double(matched) / Double(denominator)

        guard accuracy != 1.0 else {
            return DictationResult(
                isCorrect: true, accuracy: 1, diffs: [], firstErrorIndex: nil,
                expected: expected, firstErrorSummary: nil
            )
        }

        // The summary is trimmed on the common prefix/suffix so it reads as one phrase-level
        // mistake rather than a per-word debug line.
        let (prefix, userMiddle, expectedMiddle) = trimmed(expected: expectedTokens, user: userTokens)
        // With a word wrong on both sides, one word of shared leading context makes the sentence
        // read like feedback: “is play” → should be “is playing”, not “play” → “playing”.
        if !userMiddle.isEmpty && !expectedMiddle.isEmpty, prefix > 0 {
            let start = prefix - 1
            return DictationResult(
                isCorrect: false,
                accuracy: accuracy,
                diffs: diffs,
                firstErrorIndex: diffs.first?.index ?? prefix,
                expected: expected,
                firstErrorSummary: summary(
                    userMiddle: Array(userTokens[start ..< prefix + userMiddle.count]),
                    expectedMiddle: Array(expectedTokens[start ..< prefix + expectedMiddle.count])
                )
            )
        }
        return DictationResult(
            isCorrect: false,
            accuracy: accuracy,
            diffs: diffs,
            firstErrorIndex: diffs.first?.index ?? prefix,
            expected: expected,
            firstErrorSummary: summary(userMiddle: userMiddle, expectedMiddle: expectedMiddle)
        )
    }

    // MARK: - Alignment

    /// One alignment step produced by the LCS walk.
    private enum Op {
        case match(expectedIndex: Int, userIndex: Int)
        case missing(Int)
        case extra(Int)
    }

    /// Longest-common-subsequence walk. `missing`/`extra` runs become `substituted` afterwards.
    private func align(expected: [String], user: [String]) -> [Op] {
        let n = expected.count
        let m = user.count
        let width = m + 1
        // ponytail: one flat (n+1)x(m+1) Int matrix per evaluation — sentence-length input only.
        // Swap to a banded/Hirschberg walk if dictating paragraphs ever becomes a thing.
        var lcs = [Int](repeating: 0, count: (n + 1) * width)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i * width + j] = expected[i] == user[j]
                    ? lcs[(i + 1) * width + j + 1] + 1
                    : max(lcs[(i + 1) * width + j], lcs[i * width + j + 1])
            }
        }

        var ops: [Op] = []
        var i = 0
        var j = 0
        while i < n || j < m {
            if i < n, j < m, expected[i] == user[j] {
                ops.append(.match(expectedIndex: i, userIndex: j))
                i += 1
                j += 1
                continue
            }
            let drop = i < n ? lcs[(i + 1) * width + j] : -1
            let skip = j < m ? lcs[i * width + j + 1] : -1
            if drop > skip {
                ops.append(.missing(i))
                i += 1
            } else if skip > drop {
                ops.append(.extra(j))
                j += 1
            } else if j < m {
                // Tie: consume the learner's word first so `missing` runs land *after* the `extra`
                // they belong to, which is what makes `play` → `playing` a single substitution.
                ops.append(.extra(j))
                j += 1
            } else {
                ops.append(.missing(i))
                i += 1
            }
        }
        return ops
    }

    /// Step 4: collapse each run of non-matches into substitutions where the sides line up.
    private func diffs(from ops: [Op], expected: [String], user: [String]) -> [TokenDiff] {
        var out: [TokenDiff] = []
        var expectedBlock: [(index: Int, token: String)] = []
        var userBlock: [(index: Int, token: String)] = []

        func flush() {
            defer {
                expectedBlock = []
                userBlock = []
            }
            guard !expectedBlock.isEmpty || !userBlock.isEmpty else { return }
            for diff in pair(expectedBlock, userBlock) {
                out.append(TokenDiff(id: out.count, kind: diff.kind, index: diff.index,
                                     user: diff.user, expected: diff.expected))
            }
        }

        for op in ops {
            switch op {
            case .match: flush()
            case .missing(let index): expectedBlock.append((index, expected[index]))
            case .extra(let index): userBlock.append((index, user[index]))
            }
        }
        flush()
        return out
    }

    private func pair(
        _ expected: [(index: Int, token: String)],
        _ user: [(index: Int, token: String)]
    ) -> [TokenDiff] {
        guard !expected.isEmpty else {
            return user.map { TokenDiff(id: 0, kind: .extra, index: $0.index, user: $0.token, expected: nil) }
        }
        guard !user.isEmpty else {
            return expected.map { TokenDiff(id: 0, kind: .missing, index: $0.index, user: nil, expected: $0.token) }
        }

        // ponytail: greedy longest-shared-prefix pairing inside one block. It exists because the
        // single most common dictation error is an inflection (`play`→`playing`, `go`→`went`);
        // a word-similarity model would be the upgrade, not a better tie-break rule.
        var takenExpected = Set<Int>()
        var matched: [(expected: (index: Int, token: String), user: (index: Int, token: String))] = []
        for candidate in user {
            var best: Int?
            var bestScore = 0
            for (position, item) in expected.enumerated() where !takenExpected.contains(position) {
                let score = commonPrefix(candidate.token, item.token)
                if score > bestScore {
                    bestScore = score
                    best = position
                }
            }
            guard let best, bestScore > 0 else { continue }
            takenExpected.insert(best)
            matched.append((expected[best], candidate))
        }

        var out: [TokenDiff] = matched.map {
            TokenDiff(id: 0, kind: .substituted, index: $0.expected.index, user: $0.user.token, expected: $0.expected.token)
        }
        // Whatever is left on both sides pairs up positionally, then the remainder is what it is.
        let leftovers = user.enumerated().filter { _, item in !matched.contains(where: { $0.user.index == item.index }) }
        let leftoversExpected = expected.enumerated().filter { !takenExpected.contains($0.offset) }
        for (index, item) in leftovers.enumerated() where index < leftoversExpected.count {
            out.append(TokenDiff(id: 0, kind: .substituted, index: leftoversExpected[index].element.index,
                                 user: item.element.token, expected: leftoversExpected[index].element.token))
        }
        for (index, item) in leftovers.enumerated() where index >= leftoversExpected.count {
            out.append(TokenDiff(id: 0, kind: .extra, index: item.element.index, user: item.element.token, expected: nil))
        }
        for (index, item) in leftoversExpected.enumerated() where index >= leftovers.count {
            out.append(TokenDiff(id: 0, kind: .missing, index: item.element.index, user: nil, expected: item.element.token))
        }
        return out.sorted { $0.index < $1.index }
    }

    private func commonPrefix(_ a: String, _ b: String) -> Int {
        var count = 0
        for (x, y) in zip(a, b) where x == y {
            count += 1
        }
        return count
    }

    // MARK: - Human-facing summary

    /// Splits both sides at the first and last divergent word.
    private func trimmed(expected: [String], user: [String]) -> (Int, [String], [String]) {
        var prefix = 0
        while prefix < expected.count, prefix < user.count, expected[prefix] == user[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < expected.count - prefix, suffix < user.count - prefix,
              expected[expected.count - 1 - suffix] == user[user.count - 1 - suffix] {
            suffix += 1
        }
        let userMiddle = Array(user[prefix ..< user.count - suffix])
        let expectedMiddle = Array(expected[prefix ..< expected.count - suffix])
        return (prefix, userMiddle, expectedMiddle)
    }

    private func summary(userMiddle: [String], expectedMiddle: [String]) -> String {
        let written = userMiddle.joined(separator: " ")
        let wanted = expectedMiddle.joined(separator: " ")
        switch (written.isEmpty, wanted.isEmpty) {
        case (true, false): return "Missing “\(wanted)”"
        case (false, true): return "Extra “\(written)”"
        case (false, false): return "“\(written)” → should be “\(wanted)”"
        case (true, true): return "Try again."
        }
    }
}