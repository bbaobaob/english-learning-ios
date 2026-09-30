import Foundation
import Observation

/// The totals for a finished session.
public struct SessionOutcome: Sendable, Equatable {
    /// Mean accuracy across every graded result; `0` when nothing was graded.
    public let accuracy: Double
    public let xpEarned: Int
    /// Ids of the items answered wrongly, in the order they were answered.
    public let wrongIDs: [String]

    public init(accuracy: Double, xpEarned: Int, wrongIDs: [String]) {
        self.accuracy = accuracy
        self.xpEarned = xpEarned
        self.wrongIDs = wrongIDs
    }
}

/// One step of a lesson run through the session flow.
public enum SessionItem: Sendable, Identifiable {
    case exercise(Exercise)
    case dictation(DictationItem)
    case theory(LessonStep)
    case video(VideoClip)
    case audio(AudioClip)
    case examples([Example])
    case summary(takeaways: [String])

    /// Stable identity derived from the wrapped content.
    ///
    /// `.examples` and `.summary` carry no id of their own, so they borrow the first wrapped item /
    /// takeaway. Both are prefixed to keep them from colliding with an authored id.
    public var id: String {
        switch self {
        case .exercise(let exercise): "exercise:\(exercise.id)"
        case .dictation(let item): "dictation:\(item.id)"
        case .theory(let step): "theory:\(step.id)"
        case .video(let clip): "video:\(clip.id)"
        case .audio(let clip): "audio:\(clip.id)"
        case .examples(let examples): "examples:\(examples.first?.id ?? "0")"
        case .summary(let takeaways): "summary:\(takeaways.first ?? "")"
        }
    }

    /// The graded exercise, when this item is one.
    public var exercise: Exercise? {
        if case .exercise(let exercise) = self { return exercise }
        return nil
    }

    /// The dictation item, when this item is one.
    public var dictationItem: DictationItem? {
        if case .dictation(let item) = self { return item }
        return nil
    }

    /// Whether the item expects an answer rather than being read through.
    public var isGraded: Bool {
        switch self {
        case .exercise, .dictation: true
        default: false
        }
    }
}

/// Drives a run of ``SessionItem``s: grading, advancing, retrying, and the end-of-session totals.
///
/// `@MainActor` because every screen mutates it from the UI; `Observation` ships with the standard
/// library on Linux, so nothing platform-specific is imported here.
@MainActor
@Observable
public final class LearnSession {
    /// Resolved items in presentation order.
    public private(set) var items: [SessionItem]
    /// Position of the item being shown.
    public var index: Int
    /// Graded results in the order they were submitted.
    public private(set) var results: [ExerciseResult]
    /// True once the last item has been left behind.
    public private(set) var isFinished: Bool

    private let onComplete: ((SessionOutcome) -> Void)?
    private let engine = ExerciseEngine()
    /// Item index each entry of `results` belongs to; parallel to `results`.
    private var resultIndices: [Int] = []
    private var didComplete = false

    public init(items: [SessionItem], onComplete: ((SessionOutcome) -> Void)? = nil) {
        self.items = items
        self.index = 0
        self.results = []
        self.onComplete = onComplete
        self.isFinished = items.isEmpty
    }

    /// The item on screen; `nil` once the session has finished.
    public var current: SessionItem? {
        guard !isFinished, items.indices.contains(index) else { return nil }
        return items[index]
    }

    // MARK: - Grading

    /// Grades the current exercise and records the result.
    ///
    /// Non-graded items (theory, video, audio, examples, summary) return a zero-XP placeholder that
    /// is **not** recorded; use ``next()`` to move past them.
    @discardableResult
    public func submit(_ response: UserResponse) -> ExerciseResult {
        guard let item = current else {
            return ungraded(exerciseID: "", explanation: "The session is finished.")
        }
        let result: ExerciseResult
        switch item {
        case .exercise(let exercise):
            result = engine.check(exercise, response: response)
            record(result, exerciseID: exercise.id)
        case .dictation(let dictationItem):
            result = checkDictationItem(dictationItem, response: response)
        default:
            return ungraded(exerciseID: item.id, explanation: "This step is not graded.")
        }
        finishIfOnLastItem()
        return result
    }

    /// Grades typed dictation on the current item.
    @discardableResult
    public func submitDictation(_ text: String) -> ExerciseResult {
        submit(.text(text))
    }

    /// Throws away the current item's result so it can be answered again. Earlier results stay.
    ///
    /// Safe to call when nothing has been submitted yet.
    public func retry() {
        guard let last = resultIndices.last, last == index else { return }
        resultIndices.removeLast()
        results.removeLast()
    }

    /// Advances to the next item. Returns `false` once the session is over, which is also the
    /// moment `onComplete` fires — exactly once.
    @discardableResult
    public func next() -> Bool {
        guard !isFinished else { return false }
        guard index + 1 < items.count else {
            isFinished = true
            notifyCompletion()
            return false
        }
        index += 1
        return true
    }

    /// Totals across everything graded so far.
    public var outcome: SessionOutcome {
        let accuracy = results.isEmpty ? 0 : results.reduce(0) { $0 + $1.accuracy } / Double(results.count)
        return SessionOutcome(
            accuracy: accuracy,
            xpEarned: results.reduce(0) { $0 + $1.xpAwarded },
            wrongIDs: results.filter { !$0.isCorrect }.map(\.exerciseID)
        )
    }

    // MARK: - Helpers

    private func checkDictationItem(_ item: DictationItem, response: UserResponse) -> ExerciseResult {
        let written: String
        if case .text(let value) = response { written = value } else { written = "" }
        let verdict = DictationEngine().evaluate(
            userInput: written,
            expected: item.expectedText,
            accepted: item.acceptedAnswers
        )
        let result = ExerciseResult(
            exerciseID: item.id,
            isCorrect: verdict.isCorrect,
            accuracy: verdict.accuracy,
            correctAnswer: .text([item.expectedText] + item.acceptedAnswers),
            explanation: item.translation ?? "",
            diffs: verdict.diffs,
            xpAwarded: verdict.isCorrect ? item.xp : 0
        )
        record(result, exerciseID: item.id)
        return result
    }

    private func record(_ result: ExerciseResult, exerciseID: String) {
        // Re-answering replaces the current item's entry rather than stacking duplicates.
        if let last = resultIndices.last, last == index {
            results[results.count - 1] = result
        } else {
            resultIndices.append(index)
            results.append(result)
        }
    }

    private func ungraded(exerciseID: String, explanation: String) -> ExerciseResult {
        ExerciseResult(
            exerciseID: exerciseID,
            isCorrect: true,
            accuracy: 1,
            correctAnswer: .none,
            explanation: explanation,
            diffs: [],
            xpAwarded: 0
        )
    }

    /// A graded item ends as soon as it is answered, so finishing the last graded item completes
    /// the session even when trailing read-only steps follow it.
    private func finishIfOnLastItem() {
        guard index == items.count - 1 else { return }
        isFinished = true
        notifyCompletion()
    }

    private func notifyCompletion() {
        guard !didComplete else { return }
        didComplete = true
        onComplete?(outcome)
    }
}