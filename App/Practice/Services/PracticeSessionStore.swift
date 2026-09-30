import Foundation
import Observation
import EnglishCore

/// Holds the live `LearnSession` for every in-flight Practice session so a session
/// survives backgrounding, a tab switch, or a navigation pop.
///
/// Why this exists: `LearnSession` is a reference type and the only thing that
/// knows which item the learner is on and which results they have already earned.
/// A view that rebuilt its own session on `init` would restart the drill the moment
/// the learner left the tab. Nothing here grades, schedules, or counts — it only
/// hands the same object back.
///
/// ponytail: a dictionary keyed by a caller-supplied string. If Practice ever grows
/// a fifth concurrent session kind, a dedicated property per screen is clearer.
@MainActor
@Observable
final class PracticeSessionStore {

    /// Process-wide instance. SwiftUI has no app-level slot we own, and creating
    /// one per view tree would defeat the whole point.
    static let shared = PracticeSessionStore()

    /// A session that is still running, keyed by slot id.
    private var live: [String: LearnSession] = [:]

    /// A session the learner has not finished yet, or `nil`.
    func active(_ slot: String) -> LearnSession? {
        live[slot].flatMap { $0.isFinished ? nil : $0 }
    }

    /// Returns the running session for `slot`, building one only when there is
    /// nothing to resume.
    ///
    /// - Parameters:
    ///   - slot: Stable identity of the session, e.g. `"dictation:listening-skill"`.
    ///   - make: Builds a fresh session. Called at most once per unfinished run.
    func session(_ slot: String, make: () -> LearnSession) -> LearnSession {
        if let existing = active(slot) { return existing }
        let created = make()
        live[slot] = created
        return created
    }

    /// Retires the session in `slot`.
    ///
    /// Called from a `LearnSession.onComplete` closure. The screen that started the
    /// session keeps its own reference and reads `session.outcome` from it, so
    /// retiring here only means the next tap on the drill starts a clean one.
    func finish(_ slot: String) {
        live.removeValue(forKey: slot)
    }

    /// Drops any stored state for `slot`.
    func reset(_ slot: String) {
        live.removeValue(forKey: slot)
    }
}
