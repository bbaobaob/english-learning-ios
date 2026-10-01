import SwiftUI
import EnglishCore

/// The Learn tab root: the Grammar curriculum browser plus the Methods strip.
///
/// Everything is unlocked by design — there is no lock concept here, only
/// progress. Real completion comes from `ProgressStore`, never from view state.
struct LearnHomeView: View {

    @Environment(AppState.self) private var app
    /// Deferred to use time: a @Bindable cannot initialize from another
    /// property. Same pattern IELTSHomeView uses.
    private var appBinding: Bindable<AppState> { Bindable(app) }
    @State private var filter: LevelFilter = .all
    @State private var query: String = ""

    private var grammarTopics: [Topic] {
        (app.library?.allTopics ?? []).filter { $0.kind == .grammar }
    }

    /// Grammar topics after the level filter and the search text.
    private var visibleTopics: [Topic] {
        let leveled = filter.level.map { level in grammarTopics.filter { $0.level == level } } ?? grammarTopics
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
        return grammarTopics
            .filter { $0.level == .beginner }
            .first { topic in
                topic.lessons.contains { progress[$0.id]?.completed != true }
            }
    }

    /// Topics holding at least one started-but-unfinished lesson.
    private var inProgress: [Topic] {
        let progress = app.store.lessonProgress()
        return grammarTopics.filter { topic in
            topic.lessons.contains { lesson in
                guard let row = progress[lesson.id] else { return false }
                return !row.completed && row.currentStepIndex > 0
            }
        }
    }

    private var completedGrammarLessons: Int {
        let progress = app.store.lessonProgress()
        return grammarTopics.flatMap(\.lessons).filter { progress[$0.id]?.completed == true }.count
    }

    private var overallProgress: Double {
        let total = grammarTopics.flatMap(\.lessons).count
        guard total > 0 else { return 0 }
        return Double(completedGrammarLessons) / Double(total)
    }

    /// True when the learner is not searching and has not narrowed by level,
    /// which is when the personal sections are worth showing.
    private var showsPersonalSections: Bool {
        filter == .all && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack(path: appBinding.navigationPath) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                    summaryHeader

                    let methods = (app.library?.allTopics ?? []).filter { $0.kind == .methods }
                    if !methods.isEmpty {
                        NavigationLink(value: LearnRoute.methods) {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: methods.first?.icon ?? "lightbulb").font(AppFont.body(.title2))
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(Color.brand, in: .rect(cornerRadius: Radius.chip))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text("Methods").font(AppFont.body(.headline))
                                        .foregroundStyle(.primary)
                                    Text("Ten ways to study English that actually stick.").font(AppFont.body(.subheadline))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardStyle()
                        }
                        .buttonStyle(.plain)
                    }

                    LevelFilterBar(filter: $filter)

                    if visibleTopics.isEmpty {
                        EmptyStateView(
                            symbol: "magnifyingglass",
                            title: "No topics match",
                            message: query.isEmpty
                                ? "No grammar topic sits at this level yet."
                                : "Nothing in Grammar matches that word. Try a shorter one.",
                            actionTitle: "Show all topics",
                            action: {
                                query = ""
                                filter = .all
                            }
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.lg)
                    } else {
                        personalSections
                        levelSections
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.brand.opacity(0.05).ignoresSafeArea())
            .navigationTitle("Learn")
            .searchable(text: $query, prompt: "Search grammar topics and lessons")
            .navigationDestination(for: LearnRoute.self) { route in
                destination(for: route)
            }
        }
    }

    @ViewBuilder
    private func destination(for route: LearnRoute) -> some View {
        switch route {
        case .topic(let id):
            if let topic = app.library?.topic(id) {
                TopicDetailView(topic: topic)
            } else {
                EmptyStateView(
                    symbol: "exclamationmark.triangle",
                    title: "Topic unavailable",
                    message: "This topic is not in the content bundle that shipped with the app.",
                    actionTitle: "Back to Learn",
                    action: { app.navigationPath.removeLast() }
                )
            }
        case .lesson(let topicID, let lessonID):
            LessonView(topicID: topicID, lessonID: lessonID)
        case .alphabet:
            AlphabetView()
        case .alphabetListening:
            AlphabetListeningView()
        case .methods:
            MethodsView()
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
                    label: "\(Int((overallProgress * 100).rounded())) percent"
                )
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Grammar").font(AppFont.display(.title2))
                    Text("\(completedGrammarLessons) of \(grammarTopics.flatMap(\.lessons).count) lessons finished").font(AppFont.body(.subheadline))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                XPBadge(xp: app.store.learnerStats().totalXP)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Grammar progress, \(Int((overallProgress * 100).rounded())) percent, "
                    + "\(completedGrammarLessons) lessons finished"
            )

            HStack(spacing: Spacing.sm) {
                NavigationLink(value: LearnRoute.alphabet) {
                    Label("Alphabet", systemImage: "textformat").font(AppFont.body(.subheadline, weight: .semibold))
                }
                .buttonStyle(.bordered)

                if let resume = resumeRoute {
                    NavigationLink(value: resume) {
                        Label("Resume", systemImage: "play.fill").font(AppFont.body(.subheadline, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .padding(.top, Spacing.sm)
    }

    /// The store's resume point, resolved to a route through the lesson rows
    /// (the store returns a bare lesson id, the topic comes from its row).
    private var resumeRoute: LearnRoute? {
        guard let point = app.store.resumePoint(),
              let row = app.store.lessonProgress()[point.lessonID]
        else { return nil }
        return .lesson(topicID: row.topicID, lessonID: point.lessonID)
    }

    // MARK: - Sections

    @ViewBuilder
    private var personalSections: some View {
        if showsPersonalSections, let topic = startHere {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(
                    title: "Start here",
                    subtitle: "The first unfinished beginner topic",
                    actionTitle: nil,
                    action: nil
                )
                card(for: topic, subtitleOverride: nil)
            }
        }

        if showsPersonalSections, !inProgress.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(
                    title: "In progress",
                    subtitle: "Pick up where you stopped",
                    actionTitle: nil,
                    action: nil
                )
                ForEach(inProgress) { topic in
                    card(for: topic, subtitleOverride: nextLessonLine(for: topic))
                }
            }
        }
    }

    @ViewBuilder
    private var levelSections: some View {
        ForEach(Level.allCases, id: \.self) { level in
            let topics = visibleTopics.filter { $0.level == level }
            if !topics.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SectionHeader(title: level.shortTitle, subtitle: nil, actionTitle: nil, action: nil)
                    ForEach(topics) { topic in
                        card(for: topic, subtitleOverride: nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func card(for topic: Topic, subtitleOverride: String?) -> some View {
        TopicCard(
            title: topic.title,
            subtitle: subtitleOverride ?? topic.summary,
            symbol: topic.icon,
            progress: topicProgress(for: topic),
            level: topic.level.rawValue,
            isCompleted: isTopicComplete(topic),
            action: { app.navigationPath.append(LearnRoute.topic(topic.id)) }
        )
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

    /// The topic's first unfinished lesson, phrased for the card subtitle.
    private func nextLessonLine(for topic: Topic) -> String? {
        let progress = app.store.lessonProgress()
        guard let lesson = topic.lessons.first(where: { progress[$0.id]?.completed != true }) else { return nil }
        return "Next: \(lesson.title). \(lesson.summary)"
    }
}

/// The horizontal All / Beginner / Intermediate / Advanced filter.
///
/// `Chip` sits inside a real `Button` so the filter works from the keyboard and
/// from VoiceOver's activate gesture, not only from a tap.
struct LevelFilterBar: View {
    @Binding var filter: LevelFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(LevelFilter.allCases) { option in
                    Chip(text: option.title, isSelected: filter == option) {
                        Haptics.selection()
                        filter = option
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }
}
