import Foundation

/// One word-level disagreement between what the learner wrote and what was expected.
///
/// `index` is always an index into the **expected** token list, except for `.extra` where it is an
/// index into the learner's tokens (there is no expected token to point at).
public struct TokenDiff: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        /// Expected word the learner left out.
        case missing
        /// Word the learner wrote that is not in the expected sentence.
        case extra
        /// Word written where a different word was expected.
        case substituted
    }

    /// Position in ``diffs``; stable for a given evaluation.
    public let id: Int
    public let kind: Kind
    /// See the note on ``index`` above.
    public let index: Int
    /// The learner's word, `nil` for `.missing`.
    public let user: String?
    /// The expected word, `nil` for `.extra`.
    public let expected: String?

    /// Public and label-ordered: other modules build these directly in tests and previews.
    public init(id: Int, kind: Kind, index: Int = 0, user: String? = nil, expected: String? = nil) {
        self.id = id
        self.kind = kind
        self.index = index
        self.user = user
        self.expected = expected
    }
}