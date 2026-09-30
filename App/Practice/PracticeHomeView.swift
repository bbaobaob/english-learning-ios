import SwiftUI
import EnglishCore
import EnglishStore

/// The Practice tab root: the four skills, the three cross-cutting drills, and a
/// summary of where today stands.
///
/// Reads `ContentLibrary` and `ProgressStore` and nothing else. It never derives an
/// accuracy, a due date, or a count that the store or an engine could have produced.
struct PracticeHomeView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                header
                todaySummary
                skillsSection
                drillsSection
                weakestSection
                Color.clear.frame(height: Spacing.xl)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
        }
        .background(PracticeBackdrop())
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.large)
        // TODO(root-lane): the Practice tab relies on App/Root's NavigationStack (the one
        // bound to `AppState.navigationPath`). Do not wrap this view in a second stack.
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Four skills, one habit.")
                .font(AppFont.display(28, .bold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Text("Pick a skill to drill it, or take the review that is waiting for you.")
                .font(AppFont.display(15, .regular))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Today's summary

    private var todaySummary: some View {
        let streak = appState.store.streak()
        let stats = appState.store.learnerStats()
        let due = dueCount
        let dictationDue = dictationDueCount

        return VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(
                title: "Today's practice",
                subtitle: due == 0
                    ? "Nothing is due. Free practice still counts."
                    : PracticeFormat.phrase(due, "item", "items") + " waiting in review",
                actionTitle: nil,
                action: nil
            )

            // XP and streak are the two numbers worth reading at a glance, so they get
            // the shared badges rather than two more stat cards.
            HStack(spacing: Spacing.lg) {
                XPBadge(xp: streak.xpToday)
                StreakFlame(days: streak.current, isActive: streak.current > 0)

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(streak.xpToday.formatted(.number)) of \(streak.xpGoal.formatted(.number)) XP today")
                        .font(AppFont.display(14, .semibold))
                    Text(streak.longest > streak.current
                         ? "Best run: \(PracticeFormat.phrase(streak.longest, "day", "days"))."
                         : "This is your best run so far.")
                        .font(AppFont.display(12, .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .practiceFloatingGlass()
            .accessibilityElement(children: .combine)

            HStack(spacing: Spacing.md) {
                StatCard(
                    title: "Due",
                    value: PracticeFormat.count(due),
                    caption: dictationDue == 0 ? "no dictation due" : "\(dictationDue) dictation",
                    symbol: "bell.badge",
                    tint: .brand
                )
                StatCard(
                    title: "Accuracy",
                    value: PracticeFormat.percent(stats.accuracy),
                    caption: "\(PracticeFormat.count(totalExercises)) graded",
                    symbol: "target",
                    tint: .accuracy
                )
            }

            HStack(spacing: Spacing.md) {
                StatCard(
                    title: "Study time",
                    value: PracticeFormat.minutes(stats.studyMinutes),
                    caption: "all time",
                    symbol: "clock",
                    tint: .brandSoft
                )
                StatCard(
                    title: "Exercises",
                    value: PracticeFormat.count(totalExercises),
                    caption: "\(stats.lessonsCompleted) lessons done",
                    symbol: "checkmark.circle",
                    tint: .success
                )
            }

            // ponytail: minutes, exercises and accuracy are lifetime totals because
            // `learnerStats()` is the only aggregate the store exposes and it has no
            // per-day slice. Only XP and the due counts are genuinely "today". If a
            // daily rollup matters, add a `studySessions(on:)` to ProgressStore rather
            // than counting rows here.
            Text("Minutes, exercises and accuracy are lifetime totals — only XP and due counts are today's.")
                .font(AppFont.display(12, .regular))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Skills

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(
                title: "Core skills",
                subtitle: "Three levels each, from first words to exam register",
                actionTitle: nil,
                action: nil
            )

            ForEach(CoreSkill.allCases) { skill in
                if let topic = topic(for: skill) {
                    NavigationLink {
                        SkillView(topicID: topic.id, skill: skill)
                    } label: {
                        skillCard(skill, topic)
                    }
                    .buttonStyle(.plain)
                } else {
                    // A skill whose content file failed to load must not leave a hole
                    // in the grid, and must not pretend it can be opened.
                    EmptyStateView(
                        symbol: skill.fallbackSymbol,
                        title: "\(skill.title) is not available",
                        message: "This topic's content file did not load, so there is nothing to practise yet.",
                        actionTitle: nil,
                        action: nil
                    )
                }
            }
        }
    }

    private func skillCard(_ skill: CoreSkill, _ topic: Topic) -> some View {
        let progress = appState.store.topicProgress()
        let rollup = progress[topic.id]
        let completion = topic.lessonCompletion(appState.store.lessonProgress())

        return TopicCard(
            title: topic.title,
            subtitle: topic.summary.isEmpty ? skill.promise : topic.summary,
            symbol: topic.icon.isEmpty ? skill.fallbackSymbol : topic.icon,
            progress: completion,
            level: topic.level.displayName,
            isCompleted: rollup?.completedAt != nil,
            action: { Haptics.selection() }
        )
        .accessibilityValue(
            PracticeFormat.percent(completion) + " complete, "
                + (rollup.map { "\($0.exercisesDone) exercises, " + PracticeFormat.percent($0.accuracy) + " correct" }
                    ?? "no exercises yet")
        )
    }

    // MARK: - Utility rows

    /// Every graded exercise across every topic, read back from the store's rollups.
    ///
    /// A count of stored integers, not a grade: accuracy itself always comes from
    /// `learnerStats()` or a `TopicProgress` row.
    private var totalExercises: Int {
        appState.store.topicProgress().values.reduce(0) { $0 + $1.exercisesDone }
    }

    private var drillsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(
                title: "Drills",
                subtitle: "Cross-cutting practice that is not tied to one skill",
                actionTitle: nil,
                action: nil
            )

            NavigationLink {
                DictationLandingView()
            } label: {
                utilityRow(
                    symbol: "keyboard",
                    title: "Dictation drill",
                    detail: dictationDueCount == 0
                        ? "No dictation is due — practise any set"
                        : PracticeFormat.phrase(dictationDueCount, "sentence", "sentences") + " due for review",
                    tint: .brand,
                    trailing: dictationDueCount == 0 ? "Any" : "\(dictationDueCount)"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                ReviewView(topicID: nil)
            } label: {
                utilityRow(
                    symbol: "arrow.triangle.2.circlepath",
                    title: "Review queue",
                    detail: dueCount == 0
                        ? "Nothing due right now"
                        : "Spaced repetition, rescheduled after every grade",
                    tint: .streak,
                    trailing: dueCount == 0 ? "Clear" : "\(dueCount)"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                SpeakingDrillView(level: .beginner)
            } label: {
                utilityRow(
                    symbol: "mic",
                    title: "Speaking drill",
                    detail: "Record a take, play it back, compare with the model",
                    tint: .warning,
                    trailing: "Record"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func weakestSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(
                title: "Weakest skill",
                subtitle: "Where the last few attempts went wrong",
                actionTitle: nil,
                action: nil
            )

            if let recommendation {
                NavigationLink {
                    SkillView(topicID: recommendation.topic.id, skill: recommendation.skill)
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: recommendation.skill.fallbackSymbol)
                                AppFont.body(.title2)
                                .foregroundStyle(.danger)
                                .frame(width: 34)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recommendation.topic.title)
                                    .font(AppFont.display(18, .bold))
                                Text(recommendation.reason)
                                    .font(AppFont.display(14, .regular))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }

                        PracticeMeter(
                            title: "\(recommendation.rollup.correctCount) of \(recommendation.rollup.exercisesDone) correct",
                            caption: recommendation.nextStep,
                            value: recommendation.rollup.accuracy,
                            tint: .danger
                        )
                    }
                    .padding(Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            } else {
                EmptyStateView(
                    symbol: "sparkles",
                    title: "No weak spot yet",
                    message: "Answer a few exercises in any skill and this will point at the one that needs work.",
                    actionTitle: nil,
                    action: nil
                )
            }
        }
    }

    private func utilityRow(
        symbol: String,
        title: String,
        detail: String,
        tint: Color,
        trailing: String
    ) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: symbol)
                AppFont.body(.title3)
                .foregroundStyle(tint)
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.display(16, .semibold))
                Text(detail)
                    .font(AppFont.display(13, .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: Spacing.xs)

            Text(trailing)
                .font(AppFont.mono(13, .bold))
                .foregroundStyle(tint)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(tint.opacity(0.14), in: Capsule())
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Derived reads

    private func topic(for skill: CoreSkill) -> Topic? {
        appState.library.allTopics.first { $0.kind == skill.kind }
    }

    /// Everything the store says is reviewable right now.
    private var reviewQueue: ReviewQueue {
        ReviewQueue(appState.store.reviewQueue(on: Date()))
    }

    private var dueCount: Int {
        reviewQueue.dueToday(on: Date()).count
    }

    /// Dictation items that the review queue says are due.
    ///
    /// A `DictationItem` has no schedule of its own; the scheduled thing is the
    /// exercise built from it, so "due for dictation" means a due review item whose
    /// exercise is a dictation. Anything else is an offer, not a debt, which is why
    /// the row offers a free set when this is zero.
    private var dictationDueCount: Int {
        reviewQueue.dueToday(on: Date()).filter { item in
            guard item.source == .exercise else { return false }
            return appState.library.exercise(item.refID)?.kind == .dictation
        }.count
    }

    private var recommendation: WeakestSkill? {
        WeakestSkill.derive(
            skills: CoreSkill.allCases,
            topics: appState.library.allTopics,
            rollups: appState.store.topicProgress(),
            lessonRows: appState.store.lessonProgress()
        )
    }
}

/// One concrete "do this next" recommendation for a core skill.
///
/// Selection, not scoring: the lowest stored accuracy among skills the learner has
/// actually attempted wins. No new arithmetic happens here.
struct WeakestSkill {
    let skill: CoreSkill
    let topic: Topic
    let rollup: TopicProgress
    let reason: String
    let nextStep: String

    /// Picks the weakest attempted core skill, or `nil` when nothing has been attempted.
    static func derive(
        skills: [CoreSkill],
        topics: [Topic],
        rollups: [String: TopicProgress],
        lessonRows: [String: LessonProgress]
    ) -> WeakestSkill? {
        var candidates: [(CoreSkill, Topic, TopicProgress)] = []
        for skill in skills {
            guard let topic = topics.first(where: { $0.kind == skill.kind }),
                  let rollup = rollups[topic.id],
                  rollup.exercisesDone > 0 else { continue }
            candidates.append((skill, topic, rollup))
        }
        guard let weakest = candidates.min(by: { $0.2.accuracy < $1.2.accuracy }) else {
            return nil
        }

        let (skill, topic, rollup) = weakest
        let missed = rollup.exercisesDone - rollup.correctCount
        let reason = missed == 0
            ? "Perfect so far — worth keeping sharp with a mixed set."
            : PracticeFormat.phrase(missed, "missed answer", "missed answers")
                + " out of " + PracticeFormat.count(rollup.exercisesDone) + " in " + topic.title + "."

        // Resume the earliest unfinished lesson, which is where "what next" is
        // answered by the content rather than by arithmetic.
        let nextLesson = topic.lessons.first { lessonRows[$0.id]?.completed != true } ?? topic.lessons.first
        let nextStep = nextLesson.map { "Start with \($0.title)." } ?? "Open the skill to begin."

        return WeakestSkill(skill: skill, topic: topic, rollup: rollup, reason: reason, nextStep: nextStep)
    }
}

/// The Practice tab's ambient background: a soft brand wash plus a grain, so the
/// scrolling cards read as sheets on a surface rather than a flat list.
struct PracticeBackdrop: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)

            LinearGradient(
                colors: [Color.brand.opacity(0.16), Color.brandSoft.opacity(0.10), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.streak.opacity(0.10), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 320
            )
            .ignoresSafeArea()
        }
    }
}
