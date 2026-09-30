import Foundation
import EnglishCore
import EnglishStore

/// Everything the dashboard renders, derived from the store on every reload.
///
/// The Home screen holds no arithmetic: the recommendation ranking, the weak
/// topic ordering, the goal fraction and the "why this is weak" line all live
/// here, so a second screen showing the same number shows the same number.
@MainActor
@Observable
final class HomeModel {

    // Header
    var greeting: String = "Hello"
    var greetingSubtitle: String = ""
    var streak: Int = 0
    var xpToday: Int = 0

    // Daily goal
    var xpGoal: Int = 50
    var goalMet: Bool = false
    /// Remaining XP for today; `0` once the goal is met.
    var xpRemaining: Int = 0
    /// An honest estimate of minutes left, derived from observed XP rate.
    /// `nil` when today's rate is unknown, which the view shows as "—".
    var minutesRemaining: Int?

    // Glance
    var todayMinutes: Int = 0
    var exercisesDoneToday: Int = 0
    var todayAccuracy: Double?

    // Continue learning / recommendation
    var continueLesson: ContinueLesson?
    var recommendation: Recommendation?

    // Review
    var dueWordCount: Int = 0

    // Weak topics
    var weakTopics: [WeakTopic] = []

    // IELTS
    var ieltsModulesDone: Int = 0
    var ieltsModulesTotal: Int = 0
    var ieltsBandFocus: String?
    var ieltsFocusDetail: String?

    /// Transient one-line feedback for actions whose destination screen has not
    /// shipped yet.
    var dataMessage: String?

    // MARK: - Shapes

    /// The lesson the learner was last reading.
    struct ContinueLesson {
        let lessonID: String
        let topicID: String
        let lessonTitle: String
        let topicTitle: String
        let stepIndex: Int
        let stepCount: Int
        let stepLabel: String
        /// 1-based position of the lesson inside its topic.
        let lessonNumber: Int
        let topicLessonCount: Int
        var progress: Double {
            guard stepCount > 0 else { return 0 }
            return min(1, Double(stepIndex) / Double(stepCount))
        }
    }

    /// A lesson the app suggests, with the reason it was picked.
    struct Recommendation {
        let lessonID: String
        let topicID: String
        let lessonTitle: String
        let topicTitle: String
        let level: Level
        let estimatedMinutes: Int
        let reason: String
    }

    /// A topic the learner is weakest in, with the evidence.
    struct WeakTopic {
        let topicID: String
        let title: String
        let symbol: String
        let accuracy: Double
        let done: Int
        let missed: Int
        /// One plain line naming the shape of the problem.
        let explanation: String
    }

    /// The single concrete next action the dashboard suggests.
    enum RecommendedAction {
        case lesson(lessonID: String, topicID: String, stepIndex: Int)
        case review
        case topic(String)
        case ielts
    }

    struct RecommendedPractice {
        let title: String
        let detail: String
        let symbol: String
        let action: RecommendedAction
        let actionTitle: String
    }

    var recommendedPractice: RecommendedPractice?

    // MARK: - Loading

    /// Rebuilds every figure from the store and the library.
    ///
    /// - Parameters:
    ///   - store: The progress store.
    ///   - library: The content library.
    func load(store: ProgressStore, library: ContentLibrary) {
        let stats = store.learnerStats()
        let streakRecord = store.streak()
        let topics = store.topicProgress()

        // Goal first: it owns xpToday, and the header shows that figure.
        loadGoal(streakRecord: streakRecord, store: store)
        loadHeader(stats: stats)
        loadGlance(store: store)
        loadContinue(store: store, library: library)
        loadWeakTopics(topics: topics, library: library)
        loadRecommendedPractice(store: store, library: library)
        loadIELTS(topics: topics, library: library, store: store)
    }

    // MARK: - Header

    private func loadHeader(stats: LearnerStats) {
        streak = stats.streak

        if stats.totalXP == 0 && stats.lessonsCompleted == 0 {
            greeting = "Ready to start?"
            greetingSubtitle = "Your first lesson takes about twenty minutes."
            return
        }

        greeting = Greeting.text(for: Date())
        greetingSubtitle = streak > 0
            ? "Day \(streak) of your streak. Keep it going."
            : "A lesson a day is all it takes to restart a streak."
    }

    // MARK: - Daily goal

    private func loadGoal(streakRecord: StreakRecord, store: ProgressStore) {
        xpGoal = max(1, streakRecord.xpGoal)
        xpToday = streakRecord.xpToday
        goalMet = xpToday >= xpGoal
        xpRemaining = max(0, xpGoal - xpToday)

        // Honest estimate: today's observed XP per studied minute. A brand-new
        // learner has no rate yet, so the view shows "—" rather than a guess.
        let sessions = store.studySessions()
        let minutesToday = sessions
            .filter { Calendar.current.isDate($0.endedAt, inSameDayAs: Date()) }
            .reduce(0) { $0 + $1.minutes }

        if goalMet {
            minutesRemaining = 0
        } else if minutesToday > 0, xpToday > 0 {
            let rate = Double(xpToday) / Double(minutesToday)
            minutesRemaining = rate > 0 ? Int((Double(xpRemaining) / rate).rounded(.up)) : nil
        } else {
            minutesRemaining = nil
        }
    }

    // MARK: - At a glance

    private func loadGlance(store: ProgressStore) {
        let attempts = store.attempts(on: Date())
        exercisesDoneToday = attempts.done
        todayAccuracy = attempts.done > 0 ? Double(attempts.correct) / Double(attempts.done) : nil
        todayMinutes = store.studySessions()
            .filter { Calendar.current.isDate($0.endedAt, inSameDayAs: Date()) }
            .reduce(0) { $0 + $1.minutes }
    }

    var todayMinutesText: String {
        todayMinutes < 60 ? "\(todayMinutes)m" : "\(todayMinutes / 60)h \(todayMinutes % 60)m"
    }

    var todayAccuracyText: String {
        guard let value = todayAccuracy else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    // MARK: - Continue Learning

    /// Reads `resumePoint()`; falls back to a real recommendation.
    ///
    /// A lesson that cannot be resolved from the library is treated as absent
    /// rather than rendered as a broken card, because a dashboard that shows a
    /// half-truth is worse than one that shows the next thing to do.
    private func loadContinue(store: ProgressStore, library: ContentLibrary) {
        continueLesson = nil

        if let point = store.resumePoint(),
           let lesson = library.lesson(point.lessonID),
           let topic = library.topic(lessonTopicID(lesson, in: library)) {
            let siblings = library.lessons(in: topic.id)
            let number = (siblings.firstIndex { $0.id == lesson.id } ?? 0) + 1
            let stepIndex = min(max(0, point.stepIndex), max(0, lesson.steps.count - 1))
            let step = lesson.steps.indices.contains(stepIndex) ? lesson.steps[stepIndex] : nil

            continueLesson = ContinueLesson(
                lessonID: lesson.id,
                topicID: topic.id,
                lessonTitle: lesson.title,
                topicTitle: topic.title,
                stepIndex: stepIndex,
                stepCount: lesson.steps.count,
                stepLabel: Self.stepLabel(for: step),
                lessonNumber: number,
                topicLessonCount: max(1, siblings.count)
            )
            return
        }

        recommendation = Self.recommendation(store: store, library: library)
    }

    /// The topic that owns a lesson.
    ///
    /// `ContentLibrary` keys lessons by id but not by owning topic, so this is
    /// the one lookup the library does not offer directly.
    static func lessonTopicID(_ lesson: Lesson, in library: ContentLibrary) -> String {
        library.allTopics.first { $0.lessons.contains(lesson) }?.id ?? ""
    }

    /// Picks the next uncompleted lesson, preferring a topic the learner is
    /// below their own average on.
    ///
    /// Selection, in order:
    /// 1. Walk the course in canonical order from the last completed lesson
    ///    using `nextLesson(after:)`, and take the first uncompleted lesson in
    ///    a topic whose accuracy is measurably below the learner's average.
    /// 2. Otherwise take the very next uncompleted lesson in course order.
    /// 3. If every lesson is done, the recommendation is `nil` and the card
    ///    shows the completion state instead of a fake suggestion.
    static func recommendation(store: ProgressStore, library: ContentLibrary) -> Recommendation? {
        let rows = store.lessonProgress()
        let attempted = store.topicProgress().filter { $0.value.exercisesDone > 0 }

        let average = attempted.isEmpty
            ? nil
            : attempted.values.reduce(0.0) { $0 + $1.accuracy } / Double(attempted.count)

        func make(_ lesson: Lesson, reason: String) -> Recommendation? {
            guard let topicID = optionalTopicID(for: lesson, in: library) else { return nil }
            return Recommendation(
                lessonID: lesson.id,
                topicID: topicID,
                lessonTitle: lesson.title,
                topicTitle: library.topic(topicID)?.title ?? topicID,
                level: lesson.resolvedLevel(fallback: library.topic(topicID)?.level ?? .beginner),
                estimatedMinutes: library.topic(topicID)?.estimatedMinutes ?? 20,
                reason: reason
            )
        }

        // Course-order walk: the last completed lesson sets the anchor.
        let completedIDs = rows.filter(\.value.completed).map(\.key)
        let anchor = completedIDs
            .compactMap { id -> (String, Int)? in
                guard let index = library.allLessons.firstIndex(where: { $0.id == id }) else { return nil }
                return (id, index)
            }
            .max { $0.1 < $1.1 }?.0

        var cursorID = anchor ?? library.allLessons.first?.id
        var ordered: [Lesson] = []
        var seen = 0
        while let id = cursorID, let lesson = library.lesson(id), seen < library.allLessons.count {
            ordered.append(lesson)
            cursorID = library.nextLesson(after: id)?.id
            seen += 1
        }
        // Anything before the anchor is also still open, e.g. a skipped lesson.
        if let anchorID = anchor,
           let anchorIndex = library.allLessons.firstIndex(where: { $0.id == anchorID }) {
            ordered = Array(library.allLessons.prefix(anchorIndex)) + ordered
        }

        let open = ordered.filter { rows[$0.id]?.completed != true }
        guard !open.isEmpty else { return nil }

        if let average {
            if let weak = open.first(where: { lesson in
                guard let topicID = optionalTopicID(for: lesson, in: library),
                      let row = store.topicProgress()[topicID],
                      row.exercisesDone > 0 else { return false }
                // 5 points of slack: a topic one question from the average is
                // not "weak", and swinging the recommendation at that noise is
                // worse than recommending in course order.
                return row.accuracy < average - 0.05
            }) {
                let missed = store.topicProgress()[optionalTopicID(for: weak, in: library) ?? ""]?.exercisesDone ?? 0
                return make(
                    weak,
                    reason: missed > 0
                        ? "You are below your average on this topic."
                        : "This topic needs attention."
                )
            }
        }

        return make(open[0], reason: "Next in the course order.")
    }

    private static func optionalTopicID(for lesson: Lesson, in library: ContentLibrary) -> String? {
        library.allTopics.first { $0.lessons.contains(lesson) }?.id
    }

    // MARK: - Weak topics

    /// The three lowest-accuracy topics that have enough attempts to mean
    /// something.
    ///
    /// The floor of 3 attempts is the whole point of the gate: a single wrong
    /// answer on a first try would otherwise crown a topic the learner has
    /// barely touched.
    private func loadWeakTopics(topics: [String: TopicProgress], library: ContentLibrary) {
        weakTopics = topics
            .filter { $0.value.exercisesDone >= 3 }
            .sorted { $0.value.accuracy < $1.value.accuracy }
            .prefix(3)
            .map { id, row in
                let missed = max(0, row.exercisesDone - row.correctCount)
                let topic = library.topic(id)
                return WeakTopic(
                    topicID: id,
                    title: topic?.title ?? id,
                    symbol: topic?.icon ?? "questionmark",
                    accuracy: row.accuracy,
                    done: row.exercisesDone,
                    missed: missed,
                    explanation: "\(missed) of \(row.exercisesDone) wrong in \(topic?.title ?? id)."
                )
            }
    }

    func topicTitle(_ topicID: String) -> String? {
        weakTopics.first { $0.topicID == topicID }?.title
    }

    // MARK: - Recommended Practice

    /// One concrete next action, chosen from the weakest available signal.
    ///
    /// Priority: due words beat a weak topic, because a due word is already
    /// scheduled and decays if ignored; a weak topic with enough attempts beats
    /// a new lesson; with no data at all, the first lesson is the honest answer.
    private func loadRecommendedPractice(store: ProgressStore, library: ContentLibrary) {
        dueWordCount = store.reviewQueue(on: Date()).lazy.filter { $0.source == .vocabulary }.count

        if dueWordCount > 0 {
            recommendedPractice = RecommendedPractice(
                title: "Clear your due words",
                detail: "\(dueWordCount) word\(dueWordCount == 1 ? "" : "s") scheduled for review today. Ten minutes now keeps them from stacking up.",
                symbol: "character.book.closed.fill",
                action: .review,
                actionTitle: "Review \(dueWordCount) word\(dueWordCount == 1 ? "" : "s")"
            )
            return
        }

        if let weak = weakTopics.first {
            recommendedPractice = RecommendedPractice(
                title: "Practise \(weak.title)",
                detail: "\(weak.explanation) A short focused set is the fastest way to move that number.",
                symbol: weak.symbol,
                action: .topic(weak.topicID),
                actionTitle: "Practise \(weak.title)"
            )
            return
        }

        if let next = Self.recommendation(store: store, library: library) {
            recommendedPractice = RecommendedPractice(
                title: "Start \(next.lessonTitle)",
                detail: "\(next.topicTitle) · \(next.reason) About \(next.estimatedMinutes) minutes.",
                symbol: "play.circle.fill",
                action: .lesson(lessonID: next.lessonID, topicID: next.topicID, stepIndex: 0),
                actionTitle: "Start lesson"
            )
            return
        }

        if !library.allIELTSModules.isEmpty {
            recommendedPractice = RecommendedPractice(
                title: "Move into IELTS",
                detail: "Every lesson in the course is finished. The IELTS papers are the next content.",
                symbol: "globe",
                action: .ielts,
                actionTitle: "Open IELTS"
            )
            return
        }

        // Brand-new learner: point at the first lesson rather than inventing a
        // recommendation out of nothing.
        if let first = library.allLessons.first,
           let topic = library.allTopics.first(where: { $0.lessons.contains(first) }) {
            recommendedPractice = RecommendedPractice(
                title: "Start \(first.title)",
                detail: "\(topic.title) · first lesson in the course. About \(topic.estimatedMinutes) minutes.",
                symbol: "sparkles",
                action: .lesson(lessonID: first.id, topicID: topic.id, stepIndex: 0),
                actionTitle: "Start the course"
            )
            return
        }

        recommendedPractice = nil
    }

    // MARK: - IELTS

    private func loadIELTS(topics: [String: TopicProgress], library: ContentLibrary, store: ProgressStore) {
        let modules = library.allIELTSModules
        ieltsModulesTotal = modules.count

        let touched = Set(
            topics.filter { $0.value.exercisesDone > 0 && $0.key.hasPrefix("ielts") }.keys
        )
        ieltsModulesDone = modules.filter { touched.contains($0.id) }.count

        // Today's focus: the paper the learner has tried and is weakest in,
        // otherwise the first paper with an unfinished lesson, otherwise the
        // first module in the bundle.
        //
        // ponytail: TopicProgress is keyed by Topic id and the shipped IELTS
        // modules are not Topics, so this matches on the module id alone. If
        // content starts recording IELTS topics instead, extend the match.
        let byModule = modules.map { module -> (IELTSModule, Double, Int)? in
            let matching = topics[module.id].map { [$0] } ?? []
            let attempted = matching.filter { $0.exercisesDone > 0 }
            guard !attempted.isEmpty else { return nil }
            let done = matching.reduce(0) { $0 + $1.exercisesDone }
            let correct = matching.reduce(0) { $0 + $1.correctCount }
            return (module, Double(correct) / Double(done), done)
        }

        if let weakest = byModule.min(by: { $0.1 < $1.1 }), let lesson = weakest.0.lessons.first {
            ieltsBandFocus = lesson.band
            ieltsFocusDetail = "\(weakest.0.title) · \(Int((weakest.1 * 100).rounded()))% over \(weakest.2) questions"
            return
        }

        // No paper attempted yet: point at the first lesson nobody has finished.
        let lessonRows = store.lessonProgress()
        for module in modules {
            guard let lesson = module.lessons.first(where: { lessonRows[$0.id]?.completed != true }) else {
                continue
            }
            ieltsBandFocus = lesson.band
            ieltsFocusDetail = "\(module.title) · \(lesson.title)"
            return
        }

        ieltsBandFocus = nil
        ieltsFocusDetail = modules.isEmpty ? nil : "All papers complete."
    }

    // MARK: - Step labels

    /// A human label for the step the learner stopped on.
    static func stepLabel(for step: LessonStep?) -> String {
        guard let step else { return "Start" }
        switch step.type {
        case .theory: "Theory"
        case .video: "Video"
        case .audio: "Listening"
        case .examples: "Examples"
        case .practice: "Practice"
        case .exercises: "Exercises"
        case .dictation: "Dictation"
        case .listening: "Listening quiz"
        case .quiz: "Quiz"
        case .summary: "Summary"
        }
    }
}

// MARK: - Greeting

/// Time-of-day greeting text.
///
/// ponytail: three buckets, not a twelve-slot clock. The store owns every date
/// that matters for progress; this one string is presentation only.
enum Greeting {
    static func text(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 0..<5: "Still up?"
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}
