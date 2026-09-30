import Foundation
import EnglishCore
import EnglishStore

/// The JSON payload the Data section exports.
///
/// Deliberately a flat, readable shape rather than a dump of SwiftData rows:
/// the point is that a learner can open the file and understand it.
struct ProgressExport: Codable {
    struct Topic: Codable {
        let id: String
        let title: String
        let accuracy: Double
        let exercisesDone: Int
        let correctCount: Int
    }

    struct Lesson: Codable {
        let id: String
        let topicID: String
        let completed: Bool
        let currentStepIndex: Int
    }

    let exportedAt: Date
    let learner: String
    let joinedAt: Date
    let dailyGoalXP: Int
    let stats: LearnerStats
    let topics: [Topic]
    let lessons: [Lesson]
    let achievements: [String]
}

enum ProgressExporter {

    /// Builds the export payload from the store and the content library.
    ///
    /// - Parameters:
    ///   - store: The progress store.
    ///   - library: The content library, used only for topic titles.
    static func snapshot(store: ProgressStore, library: ContentLibrary) -> ProgressExport {
        let profile = store.profile()
        let stats = store.learnerStats()

        let topics = store.topicProgress()
            .map { id, row in
                ProgressExport.Topic(
                    id: id,
                    title: library.topic(id)?.title ?? id,
                    accuracy: row.accuracy,
                    exercisesDone: row.exercisesDone,
                    correctCount: row.correctCount
                )
            }
            .sorted { $0.id < $1.id }

        let lessons = store.lessonProgress()
            .map { id, row in
                ProgressExport.Lesson(
                    id: id,
                    topicID: row.topicID,
                    completed: row.completed,
                    currentStepIndex: row.currentStepIndex
                )
            }
            .sorted { $0.id < $1.id }

        return ProgressExport(
            exportedAt: Date(),
            learner: profile.name,
            joinedAt: profile.createdAt,
            dailyGoalXP: profile.dailyGoalXP,
            stats: stats,
            topics: topics,
            lessons: lessons,
            achievements: store.unlockedAchievements().sorted()
        )
    }

    /// Pretty-printed JSON for the share sheet.
    static func json(store: ProgressStore, library: ContentLibrary) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot(store: store, library: library))
    }
}
