import Foundation

/// The kind of activity a study session recorded.
///
/// Not persisted directly: `StudySessionRecord` stores ``rawValue`` in its
/// `kindRaw` column and exposes the decoded value through a computed property,
/// so a new case can be added without a store migration as long as raw values
/// are never reused.
public enum StudyKind: String, Codable, CaseIterable, Sendable {
    /// A guided lesson walked from start to finish.
    case lesson
    /// Free-form exercise practice outside a lesson.
    case practice
    /// Dictation-only study.
    case dictation
    /// Vocabulary drilling.
    case vocabulary
    /// IELTS module work.
    case ielts
    /// Spaced-repetition review.
    case review
    /// Speaking practice.
    case speaking
    /// Reading comprehension practice.
    case reading
    /// Writing practice.
    case writing
    /// Listening comprehension practice.
    case listening
}
