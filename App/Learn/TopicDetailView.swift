import SwiftUI
import EnglishCore
import EnglishStore

/// One topic: its header, its weak-area callout, and its lesson list.
///
/// Nothing here is locked. A lesson that was never opened is simply "not
/// started"; a lesson that is part-way through shows where the learner stopped.
struct TopicDetailView: View {

    let topic: Topic

    @Environment(AppState.self) private var app

    /// The learner's own lesson rows, read once per body evaluation.
    private var progress: [String: LessonProgress] { app.store.lessonProgress() }

    /// The topic rollup from the store, used for the weak-area callout.
    private var rollup: TopicProgress? { app.store.topicProgress()[topic.id] }

    private var completedCount: Int {
        topic.lessons.filter { progress[$0.id]?.completed == true }.count
    }

    private var completion: Double {
        guard !topic.lessons.isEmpty else { return 0 }
        return Double(completedCount) / Double(topic.lessons.count)
    }

    /// The first lesson the learner has not finished, if any.
    private var resumeLessonID: String? {
        topic.lessons.first { progress[$0.id]?.completed != true }?.id
    }

    private var levels: [Level] {
        Level.allCases.filter { level in topic.lessons.contains { $0.resolvedLevel(fallback: topic.level) == level } }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                header

                if let drill = weakTopicCallout {
                    drillCallout(drill)
                }

                if topic.lessons.isEmpty {
                    EmptyStateView(
                        symbol: "books.vertical",
                        title: "No lessons yet",
                        message: "This topic has no lesson content in the current bundle.",
                        actionTitle: nil,
                        action: nil
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(levels, id: \.self) { level in
                        let lessons = topic.lessons.filter { $0.resolvedLevel(fallback: topic.level) == level }
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            SectionHeader(
                                title: level.shortTitle,
                                subtitle: "\(lessons.count) lesson\(lessons.count == 1 ? "" : "s")",
                                actionTitle: nil,
                                action: nil
                            )
                            ForEach(lessons) { lesson in
                                lessonRow(lesson)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.brand.opacity(0.04).ignoresSafeArea())
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: LearnRoute.self) { route in
            switch route {
            case .lesson(let topicID, let lessonID):
                LessonView(topicID: topicID, lessonID: lessonID)
            case .alphabet:
                AlphabetView()
            case .alphabetListening:
                AlphabetListeningView()
            case .methods:
                MethodsView()
            case .topic(let id):
                if let next = app.library?.topic(id), next.id != topic.id {
                    TopicDetailView(topic: next)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: topic.icon).font(AppFont.body(.title))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.brand, in: .rect(cornerRadius: Radius.card))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(topic.title).font(AppFont.display(.title2))
                    Text(topic.summary).font(AppFont.body(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Spacing.sm) {
                        LevelPill(text: topic.level.shortTitle)
                        Label("\(topic.estimatedMinutes) min", systemImage: "clock").font(AppFont.body(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: Spacing.md) {
                ProgressRing(
                    progress: completion,
                    lineWidth: 8,
                    tint: completion >= 1 ? .success : .brand,
                    label: "\(completedCount) of \(topic.lessons.count) done"
                )
                Spacer(minLength: 0)
                if let resumeLessonID {
                    NavigationLink(value: LearnRoute.lesson(topicID: topic.id, lessonID: resumeLessonID)) {
                        Label(completedCount > 0 ? "Continue" : "Start", systemImage: "play.fill")
                            .frame(maxWidth: 260)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }

            ProgressView(value: completion)
                .tint(completion >= 1 ? .success : .brand)
                .accessibilityLabel("Topic completion")
                .accessibilityValue("\(Int((completion * 100).rounded())) percent")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .padding(.top, Spacing.sm)
    }

    // MARK: - Weak topic

    /// The topic's weak area: exercises the review queue still holds as failed.
    ///
    /// Per-exercise history lives in the store's review rows, so this reads the
    /// queue rather than re-deriving correctness here.
    private var weakTopicCallout: WeakTopic? {
        guard let rollup, rollup.exercisesDone >= 3 else { return nil }
        let missed = app.store.reviewQueue(on: .now).filter {
            $0.topicID == topic.id && !$0.lastResultCorrect
        }
        guard !missed.isEmpty else { return nil }
        return WeakTopic(missedCount: missed.count, accuracy: rollup.accuracy)
    }

    private struct WeakTopic {
        let missedCount: Int
        let accuracy: Double
    }

    private func drillCallout(_ weak: WeakTopic) -> some View {
        let isWeak = weak.accuracy < 0.7
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(
                title: isWeak ? "Needs another pass" : "Worth reviewing",
                subtitle: "\(weak.missedCount) exercise\(weak.missedCount == 1 ? "" : "s") still to get right",
                actionTitle: nil,
                action: nil
            )
            HStack(spacing: Spacing.md) {
                Image(systemName: isWeak ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath").font(AppFont.body(.title2))
                    .foregroundStyle(isWeak ? .warning : .brand)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(isWeak
                        ? "Accuracy here is \(Int((weak.accuracy * 100).rounded())) percent."
                        : "You are getting these right most of the time.").font(AppFont.body(.subheadline, weight: .semibold))
                    Text("Drill the questions you missed. Nothing is counted twice — you only gain the XP once.").font(AppFont.body(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.md)
            .background(Color.warning.opacity(0.12), in: .rect(cornerRadius: Radius.card))

            if let drillLessonID = resumeLessonID ?? topic.lessons.first?.id {
                NavigationLink(value: LearnRoute.lesson(topicID: topic.id, lessonID: drillLessonID)) {
                    Label("Drill the mistakes", systemImage: "target")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Lesson row

    private func lessonRow(_ lesson: Lesson) -> some View {
        let row = progress[lesson.id]
        let level = lesson.resolvedLevel(fallback: topic.level)
        let state = LessonRowState(
            isComplete: row?.completed == true,
            isStarted: (row?.currentStepIndex ?? 0) > 0 && row?.completed != true,
            stepCount: lesson.steps.count,
            stepIndex: row?.currentStepIndex ?? 0
        )

        return NavigationLink(value: LearnRoute.lesson(topicID: topic.id, lessonID: lesson.id)) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(lesson.title).font(AppFont.body(.headline))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if state.isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.success)
                            .accessibilityHidden(true)
                    }
                    XPBadge(xp: lesson.xp)
                }

                Text(lesson.summary).font(AppFont.body(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Spacing.sm) {
                    LevelPill(text: level.shortTitle)

                    // One dot per step-type present in the lesson, so the row
                    // shows what kind of work the lesson asks for.
                    HStack(spacing: Spacing.xs) {
                        ForEach(stepTypeOrder(lesson), id: \.self) { type in
                            Image(systemName: StepMeta.icon(type)).font(AppFont.body(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Steps: \(stepTypeOrder(lesson).map { StepMeta.title($0) }.joined(separator: ", "))")

                    Spacer(minLength: 0)

                    if state.isStarted {
                        Label("Resume \(state.stepIndex + 1)/\(state.stepCount)", systemImage: "book").font(AppFont.body(.caption, weight: .semibold))
                            .foregroundStyle(.brand)
                    } else if !state.isComplete {
                        Text("\(state.stepCount) steps").font(AppFont.body(.caption))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: lesson, state: state))
    }

    private func stepTypeOrder(_ lesson: Lesson) -> [LessonStep.StepType] {
        var seen: [LessonStep.StepType] = []
        for step in lesson.steps where !seen.contains(step.type) {
            seen.append(step.type)
        }
        return seen
    }

    private func accessibilityLabel(for lesson: Lesson, state: LessonRowState) -> String {
        let status = state.isComplete ? "Completed" : (state.isStarted ? "In progress" : "Not started")
        return "\(lesson.title). \(lesson.summary). \(status). \(lesson.xp) XP."
    }
}

/// Whether a lesson row is finished, started, or untouched.
struct LessonRowState {
    let isComplete: Bool
    let isStarted: Bool
    let stepCount: Int
    let stepIndex: Int
}
