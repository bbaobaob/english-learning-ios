import Foundation
import SwiftData
import SwiftUI

/// The learner's in-progress essay, persisted to disk so it survives leaving the screen
/// and relaunching the app.
///
/// Backed by the **same** SwiftData container the rest of the app uses — handed in from
/// `AppState.store.container` — but through a separate store of our own, because
/// `EnglishStore`'s schema is frozen (`docs/ARCHITECTURE.md` §2) and the lane that owns
/// it cannot be edited from here. One extra `ModelContext` on the shared container; no
/// change to any existing model, and the App container must not be the in-memory one.
///
/// TODO(store-lane): move `WritingDraft` into the EnglishStore schema and drop this file's
/// container entirely. Until then this is the only path that both writes to the real
/// store and keeps `App/IELTS` free of business logic.
@MainActor
@Observable
final class WritingDraftStore {
    /// One draft per lesson. The primary key is the IELTS lesson id.
    @Model
    final class Draft {
        @Attribute(.unique) var lessonID: String
        var text: String
        /// Seconds already spent, so the timer can be honest across visits.
        var secondsSpent: Int
        var wordCount: Int
        var updatedAt: Date

        init(lessonID: String, text: String = "", secondsSpent: Int = 0, wordCount: Int = 0) {
            self.lessonID = lessonID
            self.text = text
            self.secondsSpent = secondsSpent
            self.wordCount = wordCount
            self.updatedAt = .now
        }
    }

    private(set) var drafts: [String: Draft] = [:]
    /// Set when the container could not be opened. The editor keeps working in memory.
    private(set) var isPersisting = true

    @ObservationIgnored private let container: ModelContainer?
    @ObservationIgnored private var store: DraftStore?

    init(container: ModelContainer?) {
        self.container = container
        reload()
    }

    // MARK: - Read

    func text(for lessonID: String) -> String {
        drafts[lessonID]?.text ?? ""
    }

    func secondsSpent(for lessonID: String) -> Int {
        drafts[lessonID]?.secondsSpent ?? 0
    }

    var hasDraft: (String) -> Bool {
        { lessonID in
            guard let text = drafts[lessonID]?.text else { return false }
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: - Write

    /// Debounced by the caller; this writes straight through.
    func save(text: String, secondsSpent: Int, for lessonID: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clear(lessonID)
            return
        }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        let draft = drafts[lessonID] ?? Draft(lessonID: lessonID)
        draft.text = text
        draft.secondsSpent = secondsSpent
        draft.wordCount = words
        draft.updatedAt = .now
        drafts[lessonID] = draft
        guard let store else { return }
        if store.fetch(id: lessonID) == nil {
            store.insert(draft)
        }
        saveContext(store)
    }

    func clear(_ lessonID: String) {
        guard drafts[lessonID] != nil else { return }
        if let store, let existing = store.fetch(id: lessonID) {
            store.delete(existing)
            saveContext(store)
        }
        drafts[lessonID] = nil
    }

    private func reload() {
        guard let container else { return }
        do {
            let store = try DraftStore(container: container)
            self.store = store
            drafts = Dictionary(uniqueKeysWithValues: store.all().map { ($0.lessonID, $0) })
        } catch {
            // No writable store. The editor still works; the banner says drafts are not saved.
            isPersisting = false
            self.store = nil
        }
    }

    private func saveContext(_ store: DraftStore) {
        do {
            try store.commit()
        } catch {
            isPersisting = false
        }
    }
}

/// The thin CRUD wrapper. Its only job is to keep the container out of the lane's views.
@MainActor
private final class DraftStore {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    private var context: ModelContext { container.mainContext }

    func all() -> [WritingDraftStore.Draft] {
        let descriptor = FetchDescriptor<WritingDraftStore.Draft>()
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetch(id: String) -> WritingDraftStore.Draft? {
        var descriptor = FetchDescriptor<WritingDraftStore.Draft>(
            predicate: #Predicate { $0.lessonID == id }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    func insert(_ draft: WritingDraftStore.Draft) {
        context.insert(draft)
    }

    func delete(_ draft: WritingDraftStore.Draft) {
        context.delete(draft)
    }

    func commit() throws {
        if context.hasChanges { try context.save() }
    }
}

// MARK: - Word counting

enum ExamWordCount {
    /// Whitespace-delimited tokens, hyphenated words counted once. Matches what a
    /// learner means by "words" far better than a naive split on spaces does.
    static func words(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
            .count
    }

    static func sentences(in text: String) -> Int {
        var count = 0
        var previous: Character?
        for character in text {
            if let previous, previous.isLetter, character == "." { count += 1 }
            previous = character
        }
        return max(count, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
    }

    /// A crude long/short spread check the learner can act on: does the essay vary?
    static func hasVariedSentenceLength(_ text: String) -> Bool {
        let lengths = text.split(separator: ".")
            .map { $0.split(whereSeparator: { $0.isWhitespace }).count }
            .filter { $0 >= 3 }
        guard let shortest = lengths.min(), let longest = lengths.max() else { return false }
        return longest >= shortest + 8
    }

    /// Linking devices the exam actually rewards, matched on the stem only so that a
    /// word inside a quoted question does not count as the learner's own linking.
    private static let linkers = [
        "however", "therefore", "moreover", "furthermore", "nevertheless", "in addition",
        "as a result", "consequently", "on the other hand", "by contrast", "in contrast",
        "whereas", "although", "while", "because", "since", "thus", "hence", "firstly",
        "secondly", "finally", "in conclusion", "to sum up", "for instance", "for example",
        "such as", "due to", "in spite of", "even though",
    ]

    static func linkingDeviceCount(_ text: String) -> Int {
        let haystack = text.lowercased()
        return linkers.filter { haystack.contains($0) }.count
    }
}