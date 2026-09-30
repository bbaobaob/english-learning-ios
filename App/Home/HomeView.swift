import Foundation
import SwiftUI
import EnglishCore
import EnglishStore

/// The learning dashboard.
///
/// Every figure on this screen is read from `ProgressStore` and `ContentLibrary`
/// by `HomeModel`; nothing here invents a number, and there is no placeholder
/// content — an empty learner gets a real recommendation, not a grey box.
struct HomeView: View {

    @Environment(AppState.self) private var app
    @State private var model = HomeModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                header

                ContinueLearningCard(
                    model: model,
                    onOpen: { lessonID, topicID, stepIndex in
                        open(lessonID: lessonID, topicID: topicID, stepIndex: stepIndex)
                    },
                    onOpenIELTS: { app.selectedTab = .ielts }
                )

                DailyGoalCard(model: model)

                glanceRow

                VocabularyReviewCard(model: model) {
                    // TODO(design-system-lane): push the shared vocabulary review
                    // session once App/Review ships it.
                    model.dataMessage = "Review session queued for \(model.dueWordCount) words."
                }

                WeakTopicsCard(model: model) { topicID in
                    openTopicPractice(topicID: topicID)
                }

                RecommendedPracticeCard(model: model) { action in
                    perform(action)
                }

                IELTSCard(model: model) {
                    app.selectedTab = .ielts
                }

                if let message = model.dataMessage {
                    Text(message)
                        .font(AppFont.display(.footnote, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.xs)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xl)
        }
        .background(
            LinearGradient(
                colors: [Color.brandSoft.opacity(0.55), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .refreshable { reload() }
        .onAppear {
            // Coming back from a lesson must show the new state, not the state
            // this screen was built with.
            reload()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(model.greeting)
                    .font(AppFont.display(.largeTitle, weight: .bold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                Text(model.greetingSubtitle)
                    .font(AppFont.display(.subheadline, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Spacing.sm) {
                StreakFlame(days: model.streak, isActive: model.goalMet)
                XPBadge(xp: model.xpToday)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Glance

    private var glanceRow: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HomeSectionHeader(title: "Today at a glance", subtitle: nil)

            HStack(spacing: Spacing.sm) {
                StatCard(
                    title: "Studied",
                    value: model.todayMinutesText,
                    caption: "today",
                    symbol: "clock.fill",
                    tint: .brand
                )
                StatCard(
                    title: "Exercises",
                    value: "\(model.exercisesDoneToday)",
                    caption: "today",
                    symbol: "checklist",
                    tint: .success
                )
                StatCard(
                    title: "Accuracy",
                    value: model.todayAccuracyText,
                    caption: "today",
                    symbol: "scope",
                    tint: .accuracy
                )
            }
        }
    }

    // MARK: - Navigation

    private func open(lessonID: String, topicID: String, stepIndex: Int) {
        app.store.updateLessonProgress(
            lessonID: lessonID,
            topicID: topicID,
            stepIndex: stepIndex,
            lastStepID: nil
        )
        // TODO(design-system-lane): replace with a push of the shared lesson
        // player: app.navigationPath[.home].append(.lesson(lessonID, stepIndex)).
        reload()
        Haptics.selection()
    }

    private func openTopicPractice(topicID: String) {
        // TODO(design-system-lane): push the shared topic practice screen here.
        model.dataMessage = "Practising \(model.topicTitle(topicID) ?? topicID)."
        reload()
        Haptics.selection()
    }

    /// Runs the concrete action the Recommended Practice card chose.
    private func perform(_ action: HomeModel.RecommendedAction) {
        switch action {
        case .lesson(let lessonID, let topicID, let stepIndex):
            open(lessonID: lessonID, topicID: topicID, stepIndex: stepIndex)
        case .review:
            model.dataMessage = "Opening your review queue."
        case .topic(let topicID):
            openTopicPractice(topicID: topicID)
        case .ielts:
            app.selectedTab = .ielts
        }
    }

    private func reload() {
        model.load(store: app.store, library: app.library)
    }
}
