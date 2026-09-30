import SwiftUI
import EnglishCore

/// The Learn tab root: the Grammar curriculum browser.
///
/// Everything is unlocked by design — there is no lock concept here, only
/// progress. Real completion comes from `ProgressStore`, never from view state.
struct LearnHomeView: View {

    @Environment(AppState.self) private var app
    @State private var filter: LevelFilter = .all
    @State private var query: String = ""

    /// Grammar topics after the level filter and the search text.
    private var visibleTopics: [Topic] {
        let grammar = app.library.allTopics.filter { $0.kind == .grammar }
        let leveled = filter.level.map { level in grammar.filter { $0.level == level } } ?? grammar
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return leveled }
        return leveled.filter { topic in
            topic.title.localizedCaseInsensitiveContains(trimmed)
                || topic.summary.localizedCaseInsensitiveContains(trimmed)
                || topic.lessons.contains { $0.title.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    /// The first beginner topic with an unfinished lesson, if any.
    private var startHere: Topic? {
        let progress = app.store.lessonProgress()
        return app.library.allTopics
            .filter { $0.kind == .grammar && $0.level == .beginner }
            .first { topic in
                topic.lessons.contains { lesson in
                    progress[lesson.id]?.completed != true
                }
            }
    }

    /// Topics holding at least one started-but-unfinished lesson.
    private var inProgress: [Topic] {
        let progress = app.store.lessonProgress()
        return app.library.allTopics.filter { topic in
            topic.kind == .grammar && topic.lessons.contains { lesson in
                guard let row = progress[lesson.id] else { return false }
                return !row.completed && row.currentStepIndex > 0
            }
        }
    }

    private var completedGrammarLessons: Int {
        let progress = app.store.lessonProgress()
        return app.library.allTopics
            .filter { $0.kind == .grammar }
            .flatMap(\.lessons)
            .filter { progress[$0.id]?.completed == true }
            .count
    }

    private var totalGrammarLessons: Int {
        app.library.allTopics.filter { $0.kind == .grammar }.flatMap(\.lessons).count
    }

    private var overallProgress: Double {
        guard totalGrammarLessons > 0 else { return 0 }
        return Double(completedGrammarLessons) / Double(totalGrammarLessons)
    }

    var body: some View {
        NavigationStack(path: $app.navigationPath) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                    summaryHeader

                    if app.library.allTopics.filter({ $0.kind == .methods }).isEmpty == false {
                        methodsStrip
                    }

                    LevelFilterBar(filter: $filter)

                    if visibleTopics.isEmpty {
                        EmptyStateView(
                            symbol: "magnifyingglass",
                            title: "No topics match",
                            message: query.isEmpty
                                ? "No grammar topic sits at this level yet."
                                : "Nothing in Grammar matches “\(query)”. Try a shorter word.",
                            actionTitle: query.isEmpty ? nil : "Clear search",
                            action: query.isEmpty ? nil : { query = "" }
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.xl)
                    } else {
                        startHereSection
                        inProgressSection
                        byLevelSections
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.brand.opacity(0.04).ignoresSafeArea())
            .navigationTitle("Learn")
            .searchable(text: $query, prompt: "Search grammar topics and lessons")
            .navigationDestination(for: LearnRoute.self) { route in
                switch route {
                case .topic(let id):
                    if let topic = app.library.topic(id) {
                        TopicDetailView(topic: topic)
                    } else {
                        EmptyStateView(
                            symbol: "exclamationmark.triangle",
                            title: "Topic unavailable",
                            message: "This topic is not in the current content bundle.",
                            actionTitle: nil,
                            action: nil
                        )
                    }
                case .lesson(let topicID, let lessonID):
                    LessonView(topicID: topicID, lessonID: lessonID)
                case .alphabetListening:
                    AlphabetListeningView()
                }
            }
        }
    }

    // MARK: - Header

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.lg) {
                ProgressRing(
                    progress: overallProgress,
                    lineWidth: 10,
                    tint: .brand,
                    label: "\(Int((overallProgress * 100).rounded()))%"
                )
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Grammar")
                        .font(AppFont.display(.title2, weight: .bold))
                    Text("\(completedGrammarLessons) of \(totalGrammarLessons) lessons finished")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                XPBadge(xp: app.store.learnerStats().totalXP)
            }

            HStack(spacing: Spacing.sm) {
                Link(destination: URL(string: "app://alphabet")!) {
                    Label("Alphabet", systemImage: "textformat")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Opens the 26 letter course")

                if let resume = app.store.resumePoint() {
                    NavigationLink(value: LearnRoute.lesson(topicID: resume.topicID, lessonID: resume.lessonID)) {
                        Label("Resume", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .padding(.top, Spacing.sm)
    }

    private var methodsStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Methods", subtitle: "How to study, not what to study")
            ForEach(app.library.allTopics.filter { $0.kind == .methods }) { topic in
                TopicCard(
                    title: topic.title,
                    subtitle: topic.summary,
                    symbol: topic.icon,
                    progress: topicProgress(for: topic),
                    level: topic.level,
                    isCompleted: isTopicComplete(topic),
                    action: { app.navigationPath.append(LearnRoute.topic(topic.id)) }
                )
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var startHereSection: some View {
        if let topic = startHere, filter == .all, query.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: "Start here", subtitle: "The first unfinished beginner topic")
                TopicCard(
                    title: topic.title,
                    subtitle: topic.summary,
                    symbol: topic.icon,
                    progress: topicProgress(for: topic),
                    level: topic.level,
                    isCompleted: false,
                    action: { app.navigationPath.append(LearnRoute.topic(topic.id)) }
                )
            }
        }
    }

    @ViewBuilder
    private var inProgressSection: some View {
        if filter == .all, query.isEmpty, !inProgress.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: "In progress", subtitle: "Pick up where you left off")
                ForEach(inProgress) { topic in
                    TopicCard(
                        title: topic.title,
                        subtitle: nextLessonSummary(for: topic) ?? topic.summary,
                        symbol: topic.icon,
                        progress: topicProgress(for: topic),
                        level: topic.level,
                        isCompleted: false,
                        action: { app.navigationPath.append(LearnRoute.topic(topic.id)) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var byLevelSections: some View {
        ForEach(Level.allCases, id: \.self) { level in
            let topics = visibleTopics.filter { $0.level == level }
            if !topics.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SectionHeader(title: level.shortTitle, subtitle: nil)
                    ForEach(topics) { topic in
                        TopicCard(
                            title: topic.title,
                            subtitle: topic.summary,
                            symbol: topic.icon,
                            progress: topicProgress(for: topic),
                            level: topic.level,
                            isCompleted: isTopicComplete(topic),
                            action: { app.navigationPath.append(LearnRoute.topic(topic.id)) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Progress reads

    /// Fraction of a topic's lessons the learner has completed.
    private func topicProgress(for topic: Topic) -> Double {
        let progress = app.store.lessonProgress()
        let done = topic.lessons.filter { progress[$0.id]?.completed == true }.count
        guard !topic.lessons.isEmpty else { return 0 }
        return Double(done) / Double(topic.lessons.count)
    }

    private func isTopicComplete(_ topic: Topic) -> Bool {
        let progress = app.store.lessonProgress()
        return !topic.lessons.isEmpty && topic.lessons.allSatisfy { progress[$0.id]?.completed == true }
    }

    /// The title of the topic's first unfinished lesson, for the card subtitle.
    private func nextLessonSummary(for topic: Topic) -> String? {
        let progress = app.store.lessonProgress()
        guard let lesson = topic.lessons.first(where: { progress[$0.id]?.completed != true }) else { return nil }
        return "Next: \(lesson.title) — \(lesson.summary)"
    }
}

/// The horizontal All / Beginner / Intermediate / Advanced filter.
///
/// Built from `Chip` inside real buttons so it works with a keyboard and with
/// VoiceOver's "activate", not just a tap.
struct LevelFilterBar: View {
    @Binding var filter: LevelFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(LevelFilter.allCases) { option in
                    Button {
                        Haptics.selection()
                        filter = option
                    } label: {
                        Chip(text: option.title, isSelected: filter == option)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == option ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }
}
