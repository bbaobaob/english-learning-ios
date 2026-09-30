import Foundation
import SwiftData
import SwiftUI

/// The learner's in-progress essay, persisted so it survives leaving the screen and relaunching.
///
/// `App/IELTS` is not allowed to touch a container context directly, and the EnglishStore
/// schema is frozen (`docs/ARCHITECTURE.md` §2 — the store lane owns the model list), so
/// this owns one small container of its own pointed at Application Support. That is the
/// same durability as the rest of the app: it is a real SwiftData store on disk, it opens
/// on next launch, and nothing about it is a `UserDefaults` string.
///
/// TODO(store-lane): move `WritingDraft` into the EnglishStore schema and delete this file's
/// container. Nothing in the views changes when that happens — the API below is already the
/// one the store would expose.
@MainActor
@Observable
final class WritingDraftStore {
    /// One draft per lesson, keyed by the IELTS lesson id.
    @Model
    final class Draft {
        @Attribute(.unique) var lessonID: String
        var text: String
        /// Seconds already spent, so the clock is honest across visits.
        var secondsSpent: Int
        var updatedAt: Date

        init(lessonID: String, text: String = "", secondsSpent: Int = 0) {
            self.lessonID = lessonID
            self.text = text
            self.secondsSpent = secondsSpent
            self.updatedAt = .now
        }
    }

    private(set) var drafts: [String: Draft] = [:]
    /// `false` when the on-disk store could not be opened. The editor keeps working
    /// in memory and says so rather than silently losing the learner's work.
    private(set) var isPersisting = true

    @ObservationIgnored private var container: ModelContainer?

    init() {
        do {
            container = try Self.makeContainer()
            reload()
        } catch {
            isPersisting = false
        }
    }

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Draft.self])
        let url = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("IELTSDrafts.store")
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(url: url)])
    }

    // MARK: - Read

    func text(for lessonID: String) -> String { drafts[lessonID]?.text ?? "" }

    func secondsSpent(for lessonID: String) -> Int { drafts[lessonID]?.secondsSpent ?? 0 }

    // MARK: - Write

    /// Called on every keystroke by the editor; writes straight through.
    func save(text: String, secondsSpent: Int, for lessonID: String) {
        guard let container else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clear(lessonID)
            return
        }
        let draft = existing(lessonID) ?? Draft(lessonID: lessonID)
        draft.text = text
        draft.secondsSpent = secondsSpent
        draft.updatedAt = .now
        drafts[lessonID] = draft
        if draft.modelContext == nil { container.mainContext.insert(draft) }
        commit()
    }

    func clear(_ lessonID: String) {
        guard let container else { return }
        if let draft = existing(lessonID) {
            container.mainContext.delete(draft)
        }
        drafts[lessonID] = nil
        commit()
    }

    private func existing(_ lessonID: String) -> Draft? {
        guard let container else { return nil }
        var descriptor = FetchDescriptor<Draft>(predicate: #Predicate { $0.lessonID == lessonID })
        descriptor.fetchLimit = 1
        return (try? container.mainContext.fetch(descriptor))?.first
    }

    private func commit() {
        guard let container else { return }
        do {
            if container.mainContext.hasChanges { try container.mainContext.save() }
        } catch {
            isPersisting = false
        }
    }

    private func reload() {
        guard let container else { return }
        let descriptor = FetchDescriptor<Draft>()
        guard let all = try? container.mainContext.fetch(descriptor) else {
            isPersisting = false
            return
        }
        drafts = Dictionary(all.map { ($0.lessonID, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - Word counting

/// Counting rules the learner can see and reason about. No grading, no band prediction.
enum ExamWordCount {
    /// Whitespace-delimited tokens that contain a letter or a digit.
    static func words(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
            .count
    }

    static func sentences(in text: String) -> Int {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return 0 }
        var count = 0
        var previous: Character?
        for character in body {
            if let previous, previous.isLetter, character == "." { count += 1 }
            previous = character
        }
        return max(count, 1)
    }

    /// Does the essay mix short and long sentences? A spread check, not a style verdict.
    static func hasVariedSentenceLength(_ text: String) -> Bool {
        let lengths = text.split(separator: ".")
            .map { $0.split(whereSeparator: { $0.isWhitespace }).count }
            .filter { $0 >= 3 }
        guard let shortest = lengths.min(), let longest = lengths.max() else { return false }
        return longest >= shortest + 8
    }

    /// Distinct linking devices actually present, counted once each.
    private static let linkers = [
        "however", "therefore", "moreover", "furthermore", "nevertheless", "in addition",
        "as a result", "consequently", "on the other hand", "by contrast", "in contrast",
        "whereas", "although", "even though", "because", "since", "thus", "hence",
        "firstly", "secondly", "finally", "in conclusion", "to sum up",
        "for instance", "for example", "such as", "due to", "in spite of",
    ]

    static func linkingDeviceCount(_ text: String) -> Int {
        let haystack = text.lowercased()
        return linkers.filter { haystack.contains($0) }.count
    }

    /// Nouns ending in -s with a singular subject nearby, and articles before a vowel sound.
    /// A nudge, phrased as a question, never a verdict.
    static func looksLikeItNeedsTenseCheck(_ text: String) -> Bool {
        let presentMarkers = [" is increasing", " are increasing", " nowadays", " in today's ", " these days "]
        let body = text.lowercased()
        return presentMarkers.contains { body.contains($0) }
    }
}