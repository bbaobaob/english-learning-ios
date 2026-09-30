import SwiftUI
import EnglishCore

/// The Methods section: how to study English, not what to study.
///
/// Methods are taught the same way lessons are — through `LessonView` — so a
/// method gets the same steps, the same resume behaviour and the same XP. The
/// only thing this screen adds is the framing: these are techniques, and
/// ProgressStore keeps their progress under the `methods` topic like any other.
struct MethodsView: View {

    @Environment(AppState.self) private var app

    private var topic: Topic? { app.library.topic("methods") }

    private var lessons: [Lesson] { topic?.lessons ?? [] }

    private var completedCount: Int {
        let progress = app.store.lessonProgress()
        return lessons.filter { progress[$0.id]?.completed == true }.count
    }

    private var completion: Double {
        guard !lessons.isEmpty else { return 0 }
        return Double(completedCount) / Double(lessons.count)
    }

    /// The first method the learner has not finished.
    private var nextMethod: Lesson? {
        let progress = app.store.lessonProgress()
        return lessons.first { progress[$0.id]?.completed != true }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                header

                if lessons.isEmpty {
                    EmptyStateView(
                        symbol: "lightbulb",
                        title: "No methods loaded",
                        message: "The methods topic is not in the content bundle that shipped with the app.",
                        actionTitle: nil,
                        action: nil
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        SectionHeader(
                            title: "The ten methods",
                            subtitle: "Pick one and work it properly",
                            actionTitle: nil,
                            action: nil
                        )
                        ForEach(lessons) { lesson in
                            methodRow(lesson)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.brand.opacity(0.04).ignoresSafeArea())
        .navigationTitle("Methods")
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
                if let next = app.library.topic(id) {
                    TopicDetailView(topic: next)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: topic?.icon ?? "lightbulb")
                    AppFont.body(.title)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.brand, in: .rect(cornerRadius: Radius.card))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(topic?.title ?? "English Study Methods")
                        AppFont.display(.title2)
                    Text(topic?.summary ?? "Ten ways to study that actually stick.")
                        AppFont.body(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: Spacing.md) {
                ProgressRing(
                    progress: completion,
                    lineWidth: 8,
                    tint: completion >= 1 ? .success : .brand,
                    label: "\(completedCount) of \(lessons.count)"
                )
                Spacer(minLength: 0)
                if let nextMethod {
                    NavigationLink(value: LearnRoute.lesson(topicID: "methods", lessonID: nextMethod.id)) {
                        Label(completedCount > 0 ? "Continue" : "Start", systemImage: "play.fill")
                            .frame(maxWidth: 260)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .padding(.top, Spacing.sm)
    }

    private func methodRow(_ lesson: Lesson) -> some View {
        let row = app.store.lessonProgress()[lesson.id]
        let isComplete = row?.completed == true
        let isStarted = (row?.currentStepIndex ?? 0) > 0 && !isComplete

        return NavigationLink(value: LearnRoute.lesson(topicID: "methods", lessonID: lesson.id)) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : StepMeta.icon(lesson.steps.first?.type ?? .theory))
                    AppFont.body(.title3)
                    .foregroundStyle(isComplete ? .success : .brand)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(lesson.title)
                        AppFont.body(.headline)
                        .foregroundStyle(.primary)
                    Text(lesson.summary)
                        AppFont.body(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if isStarted {
                        Label("Resume", systemImage: "book")
                            AppFont.body(.caption, weight: .semibold)
                            .foregroundStyle(.brand)
                    }
                }
                Spacer(minLength: 0)
                XPBadge(xp: lesson.xp)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(lesson.title). \(lesson.summary). \(isComplete ? "Completed" : (isStarted ? "In progress" : "Not started")).")
    }
}
