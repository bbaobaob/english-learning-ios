import Foundation

/// Failures that prevent a library from loading at all.
public enum ContentLibraryError: Error, Sendable, Equatable {
    /// `content.json` is missing from the resource bundle.
    case missingIndex
    /// `content.json` exists but could not be decoded as a ``Course``.
    case malformedIndex(String)
    /// The `content` resource directory is missing from the bundle.
    case missingContentDirectory
}

/// The loaded course: topics, vocabulary, and IELTS modules, indexed for lookup.
///
/// Decoding is resilient: one malformed file appends a ``libraryDiagnostics``
/// entry and is skipped. Only a missing or unreadable `content.json` throws.
public struct ContentLibrary: Sendable {
    /// The course index, when the library was built from a bundle.
    public let course: Course?
    /// Problems found while loading; empty when everything decoded.
    public let libraryDiagnostics: [String]

    private let topics: [Topic]
    private let vocabulary: [VocabWord]
    private let modules: [IELTSModule]
    private let flattenedLessons: [Lesson]
    private let topicsByID: [String: Topic]
    private let lessonsByID: [String: Lesson]
    private let vocabByID: [String: VocabWord]
    private let ieltsLessonsByID: [String: IELTSLesson]
    private let exercisesByID: [String: Exercise]

    /// Topics in canonical course order: `content.json` order first, then file order.
    public var allTopics: [Topic] { topics }

    /// Every lesson, flattened in canonical topic-then-lesson order.
    public var allLessons: [Lesson] { flattenedLessons }

    /// Every vocabulary word across all loaded decks.
    public var allVocabulary: [VocabWord] { vocabulary }

    /// Every loaded IELTS module.
    public var allIELTSModules: [IELTSModule] { modules }

    /// Alias of ``libraryDiagnostics``.
    public var errors: [String] { libraryDiagnostics }

    /// Loads the library from the `content` resource directory of `bundle`.
    ///
    /// - Throws: ``ContentLibraryError/missingIndex`` when `content.json` is absent,
    ///   ``ContentLibraryError/malformedIndex(_:)`` when it cannot be decoded,
    ///   ``ContentLibraryError/missingContentDirectory`` when the directory is absent.
    public init(bundle: Bundle) throws {
        guard let indexURL = bundle.url(forResource: "content", withExtension: "json") else {
            throw ContentLibraryError.missingIndex
        }
        let index: Course
        do {
            index = try JSONDecoder().decode(Course.self, from: Data(contentsOf: indexURL))
        } catch {
            throw ContentLibraryError.malformedIndex(String(describing: error))
        }
        guard let directory = bundle.url(forResource: "content", withExtension: nil) else {
            throw ContentLibraryError.missingContentDirectory
        }

        var diagnostics: [String] = []
        var loadedTopics: [Topic] = []
        var loadedVocabulary: [VocabWord] = []
        var loadedModules: [IELTSModule] = []

        // Walk the whole resource directory so `topics/<id>.json` subfolders load too.
        var files: [URL] = []
        if let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) {
            for case let url as URL in enumerator where !url.hasDirectoryPath {
                files.append(url)
            }
        }

        for file in files.sorted(by: { $0.path < $1.path })
        where file.lastPathComponent != indexURL.lastPathComponent {
            let name = file.path.replacingOccurrences(of: directory.path + "/", with: "")
            guard let data = try? Data(contentsOf: file) else {
                diagnostics.append("Skipped \(name): file could not be read.")
                continue
            }
            // Order matters: a Topic is the only shape carrying `lessons`,
            // a VocabDeck the only one carrying `words`.
            if let topic = try? JSONDecoder().decode(Topic.self, from: data) {
                if topic.lessons.isEmpty {
                    diagnostics.append("Topic \(topic.id) has no lessons.")
                }
                loadedTopics.append(topic)
            } else if let deck = try? JSONDecoder().decode(VocabDeck.self, from: data) {
                loadedVocabulary.append(contentsOf: deck.words)
            } else if let module = try? JSONDecoder().decode(IELTSModule.self, from: data) {
                loadedModules.append(module)
            } else {
                diagnostics.append("Skipped \(name): not a Topic, VocabDeck, or IELTSModule.")
            }
        }

        let ordered = Self.orderTopics(loadedTopics, by: index.topicIDs)
        for topicID in index.topicIDs where !ordered.contains(where: { $0.id == topicID }) {
            diagnostics.append("content.json lists topic \(topicID) but no file was loaded for it.")
        }

        self.init(
            course: index,
            topics: ordered,
            vocabulary: loadedVocabulary,
            modules: loadedModules,
            diagnostics: diagnostics
        )
    }

    /// Builds a library from in-memory collections, for tests and previews.
    public init(topics: [Topic], vocabulary: [VocabWord], ielts: [IELTSModule]) {
        self.init(course: nil, topics: topics, vocabulary: vocabulary, modules: ielts, diagnostics: [])
    }

    private init(
        course: Course?,
        topics: [Topic],
        vocabulary: [VocabWord],
        modules: [IELTSModule],
        diagnostics: [String]
    ) {
        self.course = course
        self.topics = topics
        self.vocabulary = vocabulary
        self.modules = modules
        self.libraryDiagnostics = diagnostics
        self.topicsByID = Dictionary(topics.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.flattenedLessons = topics.flatMap(\.lessons)
        self.lessonsByID = Dictionary(
            self.flattenedLessons.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.vocabByID = Dictionary(vocabulary.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.ieltsLessonsByID = Dictionary(
            modules.flatMap(\.lessons).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.exercisesByID = Dictionary(
            self.flattenedLessons.flatMap(\.exercises).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The topic with the given id.
    public func topic(_ id: String) -> Topic? {
        topicsByID[id]
    }

    /// The lesson with the given id, in any topic.
    public func lesson(_ id: String) -> Lesson? {
        lessonsByID[id]
    }

    /// The lesson with the given id, only when it belongs to `topicID`.
    public func lesson(_ id: String, in topicID: String) -> Lesson? {
        guard let lesson = lessonsByID[id] else { return nil }
        return topicsByID[topicID]?.lessons.contains(lesson) == true ? lesson : nil
    }

    /// The vocabulary word with the given id.
    public func vocabWord(_ id: String) -> VocabWord? {
        vocabByID[id]
    }

    /// The IELTS lesson with the given id, in any module.
    public func ieltsLesson(_ id: String) -> IELTSLesson? {
        ieltsLessonsByID[id]
    }

    /// The lesson after `lessonID` in ``allLessons`` order; `nil` at the end.
    public func nextLesson(after lessonID: String) -> Lesson? {
        guard let index = flattenedLessons.firstIndex(where: { $0.id == lessonID }) else { return nil }
        let next = flattenedLessons.index(after: index)
        return next < flattenedLessons.endIndex ? flattenedLessons[next] : nil
    }

    /// The lessons of a topic, in study order.
    public func lessons(in topicID: String) -> [Lesson] {
        topicsByID[topicID]?.lessons ?? []
    }

    /// The inline exercise with the given id, searched across every lesson.
    public func exercise(_ id: String) -> Exercise? {
        exercisesByID[id]
    }

    /// Sorts `topics` to match `topicIDs`, appending any unlisted topic in file order.
    private static func orderTopics(_ topics: [Topic], by topicIDs: [String]) -> [Topic] {
        let byID = Dictionary(topics.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = topicIDs.compactMap { byID[$0] }
        let listed = Set(topicIDs)
        return ordered + topics.filter { !listed.contains($0.id) }
    }
}
