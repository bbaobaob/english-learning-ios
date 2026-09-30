import EnglishCore
import Foundation
import Observation

/// Which lessons exist and how they are grouped. Reads content only — progress
/// comes from `ProgressStore` inside the views that display it.
///
/// Built from the loaded `ContentLibrary`, so the learner sees exactly what the
/// rest of the app sees and an empty tab means the content really is missing
/// rather than that this lane's private decoder failed to find it.
@MainActor
@Observable
final class IELTSSectionModel {
    private(set) var papers: [IELTSPaper] = []
    /// A one-line note when the bundled IELTS content could not be read at all.
    private(set) var loadWarning: String?

    /// - Parameter library: The loaded course. Pass `appState.library`; the
    ///   papers are empty until it is non-`nil`, so call ``refresh(library:)``
    ///   if the content loads after this model is constructed.
    init(library: ContentLibrary?) {
        refresh(library: library)
    }

    /// Rebuilds from a (re)loaded library.
    ///
    /// Called again by the view when the library appears, because content can
    /// finish loading after the first render — a retry after a failed load, or a
    /// slow disk on first launch.
    func refresh(library: ContentLibrary?) {
        papers = library.map { IELTSCatalog.papers(from: $0.allIELTSModules) } ?? []
        loadWarning = papers.isEmpty
            ? "No IELTS lessons are in this build's content bundle."
            : nil
    }

    func paper(for skill: IELTSSkill) -> IELTSPaper? {
        papers.first { $0.skill == skill }
    }

    func lessons(for skill: IELTSSkill) -> [IELTSPaperLesson] {
        paper(for: skill)?.lessons ?? []
    }

    var skillOrder: [IELTSSkill] {
        IELTSSkill.allCases.sorted { IELTSPaper.skillOrder($0) < IELTSPaper.skillOrder($1) }
    }

    var totalLessons: Int { papers.reduce(0) { $0 + $1.lessons.count } }

    func totalMinutes(for skill: IELTSSkill) -> Int {
        lessons(for: skill).reduce(0) { $0 + $1.targetMinutes }
    }

    /// The skill the learner has spent least time on, ties broken in paper order.
    /// Used for the "next up" line on the home screen.
    func leastPractised(using totals: [IELTSSkill: Int]) -> IELTSSkill? {
        guard !lessons(for: skillOrder.first ?? .listening).isEmpty else { return nil }
        return skillOrder.min { (totals[$0] ?? 0) < (totals[$1] ?? 0) }
    }
}

/// How far one IELTS lesson has got, read out of the store's row.
struct ProgressSnapshot: Equatable {
    var isCompleted: Bool
    var currentStepIndex: Int
    var updatedAt: Date?

    /// Has the learner already started this lesson?
    var isStarted: Bool { currentStepIndex > 0 || isCompleted }

    /// "Review" beats "Resume" beats "Start".
    var resumeLabel: String {
        if isCompleted { return "Review" }
        return isStarted ? "Resume" : "Start"
    }
}