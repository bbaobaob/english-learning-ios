import Foundation
import SwiftUI
import EnglishCore
import EnglishStore

/// Everything the Profile screen renders, derived once per reload.
///
/// The screen itself does no arithmetic: this type owns the accuracy maths,
/// the ranking, and the day bucketing so the views stay declarative.
@MainActor
@Observable
final class ProfileModel {

    // Learner
    var name: String = ""
    var joinedAt: Date = Date()
    var totalXP: Int = 0
    var learnerLevel: Int = 1

    // Streak
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var totalDays: Int = 0
    var dailyGoalXP: Int = 50

    // Progress
    var studyMinutes: Int = 0
    var accuracy: Double = 0
    var lessonsCompleted: Int = 0
    var wordsMastered: Int = 0
    var reviewsDone: Int = 0
    var ieltsCompleted: Int = 0

    /// One row per skill. `progress` is `nil` when the learner has no data, so
    /// the view can show "not started" rather than a misleading 0%.
    var skills: [SkillProgress] = []

    /// Ascending accuracy, worst first.
    var weakAreas: [WeakArea] = []

    /// This month, then last month, each as a full day grid with no holes.
    var heatMaps: [HeatMapMonth] = []

    /// Minutes per day for the last 14 days, oldest first.
    var last14Days: [StudyDay] = []

    var achievements: [AchievementBadge] = []

    /// The message shown under the Data section after a reset or an export.
    var dataMessage: String?

    /// The learner-facing name for a topic id, falling back to the raw id.
    func topicTitle(_ topicID: String) -> String? {
        weakAreas.first { $0.id == topicID }?.title ?? topicID
    }

    /// Sort order for the weak-area list.
    var weakSort: WeakSort = .accuracy

    enum WeakSort: String, CaseIterable, Identifiable {
        case accuracy = "Accuracy"
        case missed = "Most missed"
        case newest = "Least practised"
        var id: String { rawValue }
    }

    struct SkillProgress: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let progress: Double?
        let detail: String
    }

    struct WeakArea: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let accuracy: Double
        let missed: Int
        let done: Int
    }

    struct HeatMapMonth: Identifiable {
        let id: String
        let title: String
        let days: [StudyDay]
    }

    struct AchievementBadge: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let isUnlocked: Bool
        let unlockedAt: Date?
        /// Current value of the tracked metric, `0` when unknown.
        let value: Int
        /// The threshold from the catalogue.
        let threshold: Int
        /// Progress toward the threshold in `0...1`.
        let progress: Double
    }

    // MARK: - Loading

    /// Rebuilds every derived value from the store.
    ///
    /// - Parameters:
    ///   - store: The progress store.
    ///   - library: The content library, used for topic titles and symbols.
    func load(store: ProgressStore, library: ContentLibrary) {
        let stats = store.learnerStats()
        let profile = store.profile()
        let streak = store.streak()

        name = profile.name
        joinedAt = profile.createdAt
        dailyGoalXP = profile.dailyGoalXP
        totalXP = stats.totalXP
        learnerLevel = max(1, totalXP / 500 + 1)

        currentStreak = streak.current
        longestStreak = streak.longest
        totalDays = streak.totalDays

        studyMinutes = stats.studyMinutes
        accuracy = stats.accuracy
        lessonsCompleted = stats.lessonsCompleted
        wordsMastered = stats.wordsMastered
        reviewsDone = stats.reviewsDone
        ieltsCompleted = stats.ieltsCompleted

        loadWeakAreas(store: store, library: library)
        loadSkills(store: store, library: library)
        loadHeatMaps(store: store)
        loadAchievements(store: store, stats: stats)
    }

    /// Records a new daily goal and refreshes everything that depends on it.
    func updateDailyGoal(_ xp: Int, store: ProgressStore, library: ContentLibrary) {
        store.setDailyGoal(xp)
        load(store: store, library: library)
    }

    /// Saves a new display name.
    func updateName(_ newName: String, store: ProgressStore) {
        store.setProfileName(newName)
        name = store.profile().name
    }

    /// Clears every stored row and reloads the empty state.
    func reset(store: ProgressStore, library: ContentLibrary) {
        store.resetAllProgress()
        load(store: store, library: library)
        dataMessage = "Progress cleared. Welcome back whenever you are ready."
    }

    // MARK: - Weak areas

    /// Re-sorts the weak-area list after the sort picker changes.
    func resortWeakAreas() {
        weakAreas = sorted(store: ProgressStore?, unsorted: weakAreas)
        weakAreas = weakAreas.sorted { lhs, rhs in
            switch weakSort {
            case .accuracy:
                return lhs.accuracy == rhs.accuracy ? lhs.missed > rhs.missed : lhs.accuracy < rhs.accuracy
            case .missed:
                return lhs.missed == rhs.missed ? lhs.accuracy < rhs.accuracy : lhs.missed > rhs.missed
            case .newest:
                return lhs.done == rhs.done ? lhs.accuracy < rhs.accuracy : lhs.done < rhs.done
            }
        }
    }

    private func loadWeakAreas(store: ProgressStore, library: ContentLibrary) {
        let rows = store.topicProgress().filter { $0.value.exercisesDone > 0 }
        let mapped = rows.map { id, row in
            WeakArea(
                id: id,
                title: library.topic(id)?.title ?? id,
                symbol: library.topic(id)?.icon ?? "questionmark",
                accuracy: row.accuracy,
                missed: max(0, row.exercisesDone - row.correctCount),
                done: row.exercisesDone
            )
        }
        weakAreas = sorted(store: store, unsorted: mapped)
    }

    private func sorted(store: ProgressStore?, unsorted: [WeakArea]) -> [WeakArea] {

    // MARK: - Skills

    /// Aggregates topic rollups into the eight skill rows.
    ///
    /// Grammar is the only skill with dedicated topics in the shipped content;
    /// the others read the `StudyKind` of the recorded sessions, and a skill
    /// with no recorded session of its kind stays `nil` rather than showing 0%.
    private func loadSkills(store: ProgressStore, library: ContentLibrary) {
        let topics = store.topicProgress()
        let sessions = store.studySessions()

        func topicAccuracy(kinds: Set<TopicKind>) -> (Double?, String) {
            let ids = library.allTopics.filter { kinds.contains($0.kind) }.map(\.id)
            let matching = ids.compactMap { topics[$0] }.filter { $0.exercisesDone > 0 }
            let done = matching.reduce(0) { $0 + $1.exercisesDone }
            guard done > 0 else { return (nil, "No attempts yet") }
            let correct = matching.reduce(0) { $0 + $1.correctCount }
            return (Double(correct) / Double(done), "\(correct) of \(done) correct")
        }

        func sessionSkill(_ kind: StudyKind) -> (Double?, String) {
            let matching = sessions.filter { $0.kind == kind }
            let minutes = matching.reduce(0) { $0 + $1.minutes }
            guard !matching.isEmpty else { return (nil, "Not practised yet") }
            let share = min(1, Double(minutes) / Double(skillsTotalMinutes))
            return (share, "\(minutes) min over \(matching.count) session\(matching.count == 1 ? "" : "s")")
        }

        let grammar = topicAccuracy(kinds: [.grammar, .alphabet])
        let vocabulary = topicAccuracy(kinds: [.vocabulary])
        let dictation = sessionSkill(.dictation)
        let listening = sessionSkill(.listening)
        let speaking = sessionSkill(.speaking)
        let reading = sessionSkill(.reading)
        let writing = sessionSkill(.writing)
        let ielts = sessionSkill(.ielts)

        skills = [
            SkillProgress(id: "grammar", title: "Grammar", symbol: "textformat", progress: grammar.0, detail: grammar.1),
            SkillProgress(id: "vocabulary", title: "Vocabulary", symbol: "character.book.closed", progress: vocabulary.0, detail: vocabulary.1),
            SkillProgress(id: "listening", title: "Listening", symbol: "headphones", progress: listening.0, detail: listening.1),
            SkillProgress(id: "speaking", title: "Speaking", symbol: "mic", progress: speaking.0, detail: speaking.1),
            SkillProgress(id: "reading", title: "Reading", symbol: "text.book", progress: reading.0, detail: reading.1),
            SkillProgress(id: "writing", title: "Writing", symbol: "pencil.tip", progress: writing.0, detail: writing.1),
            SkillProgress(id: "dictation", title: "Dictation", symbol: "pencil.and.outline", progress: dictation.0, detail: dictation.1),
            SkillProgress(id: "ielts", title: "IELTS", symbol: "globe", progress: ielts.0, detail: ielts.1)
        ]
    }

    /// Total study minutes, used as the denominator for the session-based skills.
    private var skillsTotalMinutes: Int {
        max(1, studyMinutes)
    }

    // MARK: - Heat map

    private func loadHeatMaps(store: ProgressStore) {
        let calendar = Calendar.current
        let today = Date().startOfDay

        func month(offset: Int, title: String) -> HeatMapMonth {
            let base = today.adding(months: offset)
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: base)) ?? base
            let lastDay = calendar.range(of: .day, in: .month, for: base)?.count ?? 30
            let end = start.adding(days: lastDay - 1).startOfDay
            return HeatMapMonth(id: title, title: title, days: store.studyDays(from: start, through: end))
        }

        let thisMonth = month(offset: 0, title: "This month")
        let lastMonth = month(offset: -1, title: "Last month")
        heatMaps = [thisMonth, lastMonth]

        let start = today.adding(days: -13).startOfDay
        last14Days = store.studyDays(from: start, through: today)
    }

    // MARK: - Achievements

    private func loadAchievements(store: ProgressStore, stats: LearnerStats) {
        let unlocked = store.unlockedAchievements()
        let dates = store.achievementUnlockDates()
        achievements = AchievementEngine.catalogue.map { badge in
            let value = badge.value(in: stats)
            return AchievementBadge(
                id: badge.id,
                title: badge.title,
                detail: badge.detail,
                symbol: badge.symbol,
                isUnlocked: unlocked.contains(badge.id) || badge.isUnlocked(by: stats),
                unlockedAt: dates[badge.id],
                value: value,
                threshold: badge.threshold,
                progress: min(1, Double(value) / Double(max(1, badge.threshold)))
            )
        }
    }
}

// MARK: - Month arithmetic

extension Date {
    /// This instant shifted by whole months, keeping the day when it exists.
    ///
    /// - Parameter months: The offset, which may be negative.
    func adding(months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: self) ?? self
    }
}
