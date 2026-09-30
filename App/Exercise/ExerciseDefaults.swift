import SwiftUI
import EnglishCore

/// The default instruction for each kind, used when the content omits one.
///
/// The content's `instruction` always wins. These exist so that a topic author
/// writing eight exercises does not also have to write eight identical
/// sentences, and so the phrasing is identical across every exercise of a kind
/// — a learner should not have to re-read the instruction to learn what
/// "rearrange" means.
enum ExerciseDefaults {
    /// The instruction shown for `kind` when the exercise has none.
    static func instruction(for kind: ExerciseKind) -> String {
        switch kind {
        case .multipleChoice: "Choose the best answer."
        case .multiSelect: "Choose every answer that applies."
        case .fillInTheBlank: "Type the missing word."
        case .dictation: "Listen and type exactly what you hear."
        case .listening, .listeningComprehension: "Listen, then answer the question."
        case .typeTheAnswer: "Type your answer."
        case .trueFalse: "Decide whether the statement is true or false."
        case .matching: "Tap a word, then tap its match."
        case .rearrangeWords: "Tap the words in the right order."
        case .sentenceCompletion: "Complete the sentence."
        case .errorCorrection, .grammarCorrection: "Type the sentence with the mistake fixed."
        case .wordFormation: "Type the missing form of the word."
        case .translation: "Translate the sentence into English."
        case .reading: "Read the passage and answer the question."
        }
    }

    /// Whether this kind is answered by typing, which decides whether the
    /// word-level diff highlighting applies.
    static func isTextual(_ kind: ExerciseKind) -> Bool {
        switch kind {
        case .fillInTheBlank, .dictation, .typeTheAnswer, .sentenceCompletion,
             .errorCorrection, .wordFormation, .translation, .grammarCorrection:
            true
        default:
            false
        }
    }

    /// Whether the answer is a tap rather than a keyboard entry.
    static func isSelection(_ kind: ExerciseKind) -> Bool {
        switch kind {
        case .multipleChoice, .multiSelect, .reading, .listening, .listeningComprehension:
            true
        default:
            false
        }
    }
}

/// The single answer string a `UserResponse` carries, for a result panel.
///
/// Grading has already happened in `LearnSession`; this only formats the
/// already-correct answer so it can be read.
enum AnswerDisplay {
    /// A human-readable rendering of `answer`, in the vocabulary the exercise
    /// used. `exercise` supplies the option and word-bank labels, because a
    /// bare item id is not something a learner can act on.
    static func text(for answer: Answer, exercise: Exercise) -> String {
        switch answer.values {
        case .text(let values):
            values.first ?? ""
        case .choice(let ids):
            labels(for: ids, in: exercise.items)
        case .order(let tokens):
            tokens.joined(separator: " ")
        case .pairs(let map):
            // Sorted by key so the answer reads the same way every time.
            map.keys.sorted().compactMap { key in
                guard let value = map[key] else { return nil }
                return "\(label(for: key, in: exercise.items)) → \(value)"
            }.joined(separator: ", ")
        case .boolean(let flag):
            flag ? "True" : "False"
        case .none:
            ""
        }
    }

    private static func labels(for ids: [String], in items: [ExerciseItem]) -> String {
        ids.map { label(for: $0, in: items) }.joined(separator: ", ")
    }

    private static func label(for id: String, in items: [ExerciseItem]) -> String {
        items.first { $0.id == id }?.text ?? id
    }
}
