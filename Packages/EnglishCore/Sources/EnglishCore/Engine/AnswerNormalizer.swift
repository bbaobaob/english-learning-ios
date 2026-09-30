import Foundation

/// Folds two answers to the same string so graders only compare meaning, not decoration.
///
/// Normalisation is deliberately conservative: NFKD + diacritic folding, case folding, removal of
/// `.,!?;:"()[]{}` and typographic quotes (with the apostrophe **kept**, so `don't` stays `don't`),
/// whitespace collapsed, trimmed. It does not stem, reorder, or fold British/American spelling —
/// those are different words for this app.
public struct AnswerNormalizer: Sendable {
    /// Punctuation dropped outright. The apostrophe is deliberately absent.
    private static let dropped: Set<Unicode.Scalar> = Set(".,!?;:\"()[]{}“”‘’—–…".unicodeScalars)

    /// Typographic apostrophes folded to `'`, so `don’t` and `don't` compare equal.
    private static let apostrophes: Set<Unicode.Scalar> = Set("\u{2019}\u{02BC}\u{FF07}".unicodeScalars)

    public init() {}

    /// The comparable form of `text`: folded, lowercased, unpunctuated, whitespace-collapsed.
    public func normalize(_ text: String) -> String {
        var view = String.UnicodeScalarView()
        view.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.decomposedStringWithCanonicalMapping.unicodeScalars {
            if Self.apostrophes.contains(scalar) {
                view.append("'")
                continue
            }
            guard !Self.dropped.contains(scalar) else { continue }
            // Diacritic folding: combining marks left behind by NFKD carry no meaning here.
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .enclosingMark: continue
            default: view.append(scalar)
            }
        }
        return String(view)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Whitespace tokens of the normalised form.
    public func tokens(_ text: String) -> [String] {
        let normalized = normalize(text)
        return normalized.isEmpty ? [] : normalized.split(separator: " ").map(String.init)
    }

    /// Whether two answers mean the same thing to the grader.
    public func isEquivalent(_ a: String, _ b: String) -> Bool {
        normalize(a) == normalize(b)
    }
}