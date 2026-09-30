import Foundation
import SwiftData
import EnglishCore

/// The single persistence seam between the app and SwiftData.
///
/// The store owns one `ModelContext` on the main actor, so every method is safe
/// to call from a view's `.task`. Mutations save eagerly, which is what makes
/// the kill-and-reopen tests in `EnglishStoreTests` pass: nothing waits for app
/// teardown.
///
/// All date arithmetic is delegated to `EnglishCore` (`StreakCalculator`,
/// `SpacedRepetition`) — this type stores and retrieves, it does not decide
/// what "correct" or "consecutive" means.
@MainActor
public final class ProgressStore {

    /// The model schema, built once so `makeContainer(_:)` and the inits agree.
    private static let schema = Schema([
        UserProfile.self,
        TopicProgress.self,
        LessonProgress.self,
        AttemptRecord.self,
        ReviewState.self,
        VocabState.self,
        StudySessionRecord.self,
        StreakRecord.self,
        AchievementState.self,
        MediaBookmark.self,
        NotificationPref.self,
    ])

    /// A model that failed the schema check in ``init(container:calendar:now:)``.
    public enum StoreError: Error, Equatable {
        /// The container was built without some of this package's models.
        case incompleteSchema(missing: [String])
    }

    // Storage and helpers below are module-internal rather than `private`
    // because `ProgressStore+Collections.swift` extends this type from another
    // file, and Swift's `private` is file-scoped for extensions. They are not
    // public API and the app cannot reach them.

    /// The vocabulary word counts as mastered at this mastery value.
    static let masteryThreshold = 1.0

    /// The container backing this store.
    public let container: ModelContainer

    /// The context every read and write runs through.
    var context: ModelContext { container.mainContext }

    /// The calendar used for day boundaries in streak and XP accounting.
    let calendar: Calendar

    /// The clock, injected so tests never depend on the wall clock.
    let now: @Sendable () -> Date

    /// Spaced-repetition scheduler bound to the store's clock.
    lazy var repetition = SpacedRepetition(now: now)

    /// Streak calculator bound to the store's calendar and clock.
    lazy var streaks = StreakCalculator(calendar: calendar, now: now)

    // MARK: - Lifecycle

    /// Creates a store on a caller-supplied container.
    ///
    /// The designated initialiser. The container must have been built from
    /// ``makeContainer(_:)`` (or an equivalent schema), because a partial
    /// schema fails later with a far less obvious error.
    ///
    /// - Parameters:
    ///   - container: The container to read and write through.
    ///   - calendar: The calendar defining day boundaries.
    ///   - now: The clock used for timestamps, injectable for tests.
    /// - Throws: ``StoreError/incompleteSchema(missing:)`` if `container` lacks
    ///   any of this package's models.
    public init(
        container: ModelContainer,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        let present = Set(container.schema.entities.map(\.name))
        let missing = Self.schema.entities.map(\.name).filter { !present.contains($0) }
        guard missing.isEmpty else {
            throw StoreError.incompleteSchema(missing: missing)
        }
        self.container = container
        self.calendar = calendar
        self.now = now
    }

    /// Creates a store on an existing container, using the current calendar.
    ///
    /// - Parameter container: The container to read and write through.
    /// - Throws: ``StoreError/incompleteSchema(missing:)`` if `container` lacks
    ///   any of this package's models.
    public convenience init(container: ModelContainer) throws {
        try self.init(container: container, calendar: .current, now: Date.init)
    }

    /// Creates a throwaway store backed by memory only.
    ///
    /// For tests and previews. Data disappears with the returned store, so a
    /// kill-and-reopen test needs a real on-disk configuration instead.
    ///
    /// - Parameter inMemory: Must be `true`; the parameter exists so call sites
    ///   read as intent rather than as a hard-coded factory call.
    /// - Throws: Any error `ModelContainer` raises for this schema.
    public convenience init(inMemory: Bool) throws {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        try self.init(container: Self.makeContainer(configuration))
    }

    /// Builds a container carrying every model in this package.
    ///
    /// - Parameter configuration: Where the data lives.
    /// - Returns: A container ready for ``init(container:calendar:now:)``.
    /// - Throws: Any error `ModelContainer` raises for this schema.
    public static func makeContainer(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: - Reading progress

    /// Returns every topic rollup, keyed by topic id.
    ///
    /// - Returns: Live models; treat them as read-only outside the store.
    /// - Complexity: O(n) in the number of topic rows.
    public func topicProgress() -> [String: TopicProgress] {
        Dictionary(uniqueKeysWithValues: allRows(TopicProgress.self).map { ($0.topicID, $0) })
    }

    /// Returns every lesson position row, keyed by lesson id.
    ///
    /// - Returns: Live models; treat them as read-only outside the store.
    /// - Complexity: O(n) in the number of lesson rows.
    public func lessonProgress() -> [String: LessonProgress] {
        Dictionary(uniqueKeysWithValues: allRows(LessonProgress.self).map { ($0.lessonID, $0) })
    }

    /// Returns the lesson to resume for the Home "Continue Learning" button.
    ///
    /// The most recently touched lesson that is not yet completed, so the target
    /// survives an app relaunch: it is read back from the store, never rebuilt
    /// from in-memory session state.
    ///
    /// - Returns: The lesson id and step index, or `nil` when nothing is in
    ///   progress.
    /// - Complexity: O(n log n) in the number of lesson rows, from the sort.
    public func resumePoint() -> (lessonID: String, stepIndex: Int)? {
        let rows = try? context.fetch(
            FetchDescriptor<LessonProgress>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        )
        guard let row = (rows ?? []).first(where: { !$0.completed }) else { return nil }
        return (row.lessonID, row.currentStepIndex)
    }

    // MARK: - Writing progress

    /// Records a graded attempt and everything derived from it.
    ///
    /// Persists an `AttemptRecord`, rolls the attempt into the topic's cached
    /// accuracy, and upserts the review schedule: a wrong answer is graded
    /// `SpacedRepetition.Grade.again` (due today, ease penalised) and a correct
    /// one `Grade.good` (first repetition → due tomorrow).
    ///
    /// - Parameters:
    ///   - r: The graded result.
    ///   - topicID: The topic the exercise belongs to.
    ///   - lessonID: The lesson the attempt was made in, when there is one.
    /// - Complexity: O(n) in the number of stored review rows.
    public func recordAttempt(_ r: ExerciseResult, topicID: String, lessonID: String?) {
        context.insert(
            AttemptRecord(
                exerciseID: r.exerciseID,
                topicID: topicID,
                isCorrect: r.isCorrect,
                accuracy: r.accuracy,
                // ExerciseResult carries no raw input, so the free-text column
                // stays empty; the UI shows the graded result directly.
                userText: nil,
                createdAt: now()
            )
        )

        let topic = fetchOrInsert(TopicProgress.self, { $0.topicID == topicID }) {
            TopicProgress(topicID: topicID)
        }
        topic.exercisesDone += 1
        if r.isCorrect { topic.correctCount += 1 }
        topic.accuracy = topic.exercisesDone == 0
            ? 0
            : Double(topic.correctCount) / Double(topic.exercisesDone)

        let itemID = "\(ReviewItem.Source.exercise.rawValue):\(r.exerciseID)"
        let existing = allRows(ReviewState.self).first { $0.itemID == itemID }
        // The frozen schema has no createdAt column, so a first sighting falls
        // back to its own due date and every later read reuses that same value.
        let createdAt = existing?.dueDate ?? now()
        let seed = existing?.reviewItem(on: createdAt) ?? ReviewItem(
            source: .exercise,
            refID: r.exerciseID,
            topicID: topicID,
            dueDate: now(),
            createdAt: createdAt
        )
        let row = fetchOrInsert(ReviewState.self, { $0.itemID == itemID }) {
            ReviewState(
                itemID: itemID,
                dueDate: now(),
                source: ReviewItem.Source.exercise.rawValue,
                refID: r.exerciseID,
                topicID: topicID
            )
        }
        row.apply(repetition.schedule(seed, grade: r.isCorrect ? .good : .again))

        persist()
    }

    /// Marks a lesson finished and banks its XP.
    ///
    /// `xp` is recorded as a zero-minute `StudyKind.lesson` session so
    /// `learnerStats().totalXP` includes it; callers that also call
    /// ``registerStudy(minutes:xp:kind:)`` for the same lesson would count the
    /// XP twice.
    ///
    /// - Parameters:
    ///   - lessonID: The lesson that was completed.
    ///   - topicID: The topic that owns it.
    ///   - xp: The XP the completion earned.
    /// - Complexity: O(n) in the number of lesson rows.
    public func completeLesson(_ lessonID: String, topicID: String, xp: Int) {
        let instant = now()
        let row = fetchOrInsert(LessonProgress.self, { $0.lessonID == lessonID }) {
            LessonProgress(lessonID: lessonID, topicID: topicID, updatedAt: instant)
        }
        row.topicID = topicID
        row.completed = true
        row.updatedAt = instant

        let topic = fetchOrInsert(TopicProgress.self, { $0.topicID == topicID }) {
            TopicProgress(topicID: topicID)
        }
        // ponytail: a topic counts as done the first time any of its lessons is
        // completed; the store cannot see the lesson count without the content
        // library. Recompute properly if the topic grid ever needs a percentage.
        if topic.completedAt == nil { topic.completedAt = instant }

        if xp > 0 {
            context.insert(
                StudySessionRecord(
                    startedAt: instant,
                    endedAt: instant,
                    minutes: 0,
                    xpEarned: xp,
                    kind: .lesson
                )
            )
        }
        persist()
    }

    /// Records where the learner stopped inside a lesson.
    ///
    /// Not in the frozen contract, but ``resumePoint()`` is unreachable without
    /// it and the app is not allowed to touch the context directly.
    ///
    /// - Parameters:
    ///   - lessonID: The lesson being read.
    ///   - topicID: The topic that owns it.
    ///   - stepIndex: The index to resume at.
    ///   - lastStepID: The last step visited, for deep-link restore.
    /// - Complexity: O(n) in the number of lesson rows.
    public func updateLessonProgress(
        lessonID: String,
        topicID: String,
        stepIndex: Int,
        lastStepID: String?
    ) {
        let row = fetchOrInsert(LessonProgress.self, { $0.lessonID == lessonID }) {
            LessonProgress(lessonID: lessonID, topicID: topicID, updatedAt: now())
        }
        row.topicID = topicID
        row.currentStepIndex = stepIndex
        row.completed = false
        row.lastStepID = lastStepID
        row.updatedAt = now()
        persist()
    }
}

// MARK: - Helpers
//
// Module-internal so `ProgressStore+Collections.swift` can reach them; not public API.

extension ProgressStore {

    /// Fetches every row of a model.
    ///
    /// ponytail: fetches the whole table and filters in Swift. The rollup and
    /// preference tables are content-sized and stay small; `AttemptRecord` is
    /// the one table that grows without bound, so add a `#Predicate` aggregate
    /// or a daily counter table before the attempt log reaches six figures.
    func allRows<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    /// Returns the matching row, inserting a freshly built one when absent.
    ///
    /// - Parameters:
    ///   - type: The model type to look up.
    ///   - match: The key predicate.
    ///   - make: Builds the row when there is no match.
    /// - Returns: The existing row, or the new one already inserted.
    /// - Complexity: O(n) in the number of rows of `type`.
    func fetchOrInsert<T: PersistentModel>(
        _ type: T.Type,
        _ match: (T) -> Bool,
        make makeRow: () -> T
    ) -> T {
        if let existing = allRows(type).first(where: match) { return existing }
        let created = makeRow()
        context.insert(created)
        return created
    }

    /// Returns the single streak row, inserting an empty one on first use.
    ///
    /// - Complexity: O(n) in the number of streak rows, which is one.
    func streakRow() -> StreakRecord {
        fetchOrInsert(StreakRecord.self, { _ in true }) {
            StreakRecord(xpGoal: allRows(UserProfile.self).first?.dailyGoalXP ?? 50)
        }
    }

    /// Counts back the consecutive days whose summed session XP met the goal.
    ///
    /// Days with no session break the run; the run is anchored on the most
    /// recent session day, not on today, so an unopened app cannot truncate it.
    ///
    /// - Parameters:
    ///   - sessions: Every stored study session.
    ///   - goal: The daily XP goal to clear.
    /// - Returns: The run length, `0` when no day has met the goal.
    /// - Complexity: O(n log n), from the sort.
    func dailyGoalStreak(sessions: [StudySessionRecord], goal: Int) -> Int {
        guard goal > 0 else { return 0 }
        var xpByDay: [Date: Int] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.endedAt)
            xpByDay[day, default: 0] += session.xpEarned
        }
        var run = 0
        var cursor: Date? = xpByDay.keys.max()
        while let day = cursor, (xpByDay[day] ?? 0) >= goal {
            run += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            cursor = previous
        }
        return run
    }

    /// Saves the context, reporting nothing to the caller.
    ///
    /// ponytail: a save failure here is swallowed because the frozen signatures
    /// return no `throws` and rethrowing would push error handling into every
    /// view. A failed autosave resurfaces at the next launch; when that stops
    /// being acceptable, change the mutators to `throws`.
    func persist() {
        try? context.save()
    }

    /// Whether two instants fall on the same calendar day.
    func isSameDay(_ lhs: Date?, _ rhs: Date) -> Bool {
        guard let lhs else { return false }
        return calendar.isDate(lhs, inSameDayAs: rhs)
    }
}
