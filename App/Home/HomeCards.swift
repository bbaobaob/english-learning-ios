import SwiftUI
import EnglishCore
import EnglishStore

// The five dashboard cards. Each is a pure function of `HomeModel`.

// MARK: - Section header

/// A Home section title on the floating glass surface.
struct HomeSectionHeader: View {

    let title: String
    var subtitle: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.display(.title3, weight: .bold))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.display(.subheadline, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .liquidGlass(cornerRadius: Radius.pill)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: title)
    }
}

// MARK: - Continue Learning

/// The primary action: resume what was open, or start what should be next.
///
/// This card floats above the scroll with the glass treatment because it is the
/// one thing the learner came to the app to do.
struct ContinueLearningCard: View {

    let model: HomeModel
    let onOpen: (String, String, Int) -> Void
    /// Used only by the "course complete" state, which has no lesson to open.
    let onOpenIELTS: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String {
        if model.continueLesson != nil { return "Continue learning" }
        return model.recommendation == nil ? "Course complete" : "Recommended lesson"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: model.continueLesson != nil ? "play.circle.fill" : "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .accessibilityHidden(true)

                Text(title)
                    .font(AppFont.display(.caption, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            if let lesson = model.continueLesson {
                body(for: .resume(lesson))
            } else if let rec = model.recommendation {
                body(for: .recommendation(rec))
            } else {
                completedBody
            }
        }
        // Padding first, then the glass, so the material sits on top of the
        // final geometry rather than behind it.
        .padding(Spacing.lg)
        .liquidGlass(cornerRadius: Radius.card)
        .padding(.vertical, Spacing.xs)
        // The one deliberate motion on the dashboard: the card the learner came
        // for lifts into place, everything else on the screen is still.
        .offset(y: appeared ? 0 : 14)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { appeared = true }
        }
    }

    @State private var appeared = false

    private enum Payload {
        case resume(HomeModel.ContinueLesson)
        case recommendation(HomeModel.Recommendation)
    }

    @ViewBuilder
    private func body(for payload: Payload) -> some View {
        switch payload {
        case .resume(let lesson):
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(lesson.lessonTitle)
                    .font(AppFont.display(.title2, weight: .bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(lesson.topicTitle) · Lesson \(lesson.lessonNumber) of \(lesson.topicLessonCount) · \(lesson.stepLabel)")
                    .font(AppFont.display(.subheadline, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ProgressView(value: lesson.progress)
                    .tint(Color.brand)
                    .accessibilityLabel("Lesson progress")
                    .accessibilityValue("\(Int((lesson.progress * 100).rounded())) percent")

                PrimaryButton(title: "Resume \(lesson.stepLabel.lowercased())", symbol: "play.fill") {
                    onOpen(lesson.lessonID, lesson.topicID, lesson.stepIndex)
                }
                .accessibilityHint("Opens \(lesson.lessonTitle) at the \(lesson.stepLabel) step")
            }

        case .recommendation(let rec):
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(rec.lessonTitle)
                    .font(AppFont.display(.title2, weight: .bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(rec.topicTitle) · \(rec.reason) · about \(rec.estimatedMinutes) min")
                    .font(AppFont.display(.subheadline, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Spacing.xs) {
                    LevelPill(text: rec.level.rawValue.capitalized)
                }

                PrimaryButton(title: "Start lesson", symbol: "play.fill") {
                    onOpen(rec.lessonID, rec.topicID, 0)
                }
                .accessibilityHint("Starts \(rec.lessonTitle) in \(rec.topicTitle)")
            }
        }
    }

    /// Every lesson done. Real state, honestly stated, with a route onward
    /// rather than a dead end.
    private var completedBody: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Nothing left in the course")
                .font(AppFont.display(.title2, weight: .bold))

            Text("Every lesson is finished. Keep your vocabulary sharp with a daily review, or move into the IELTS papers.")
                .font(AppFont.display(.subheadline, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecondaryButton(title: "IELTS practice", symbol: "globe") {
                onOpenIELTS()
            }
            .accessibilityHint("Opens the IELTS tab")
        }
    }
}

// MARK: - Daily goal

/// XP earned today against the goal, with an honest time hint.
struct DailyGoalCard: View {

    let model: HomeModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double {
        guard model.xpGoal > 0 else { return 0 }
        return min(1, Double(model.xpToday) / Double(model.xpGoal))
    }

    var body: some View {
        HStack(spacing: Spacing.lg) {
            ProgressRing(
                progress: progress,
                lineWidth: 10,
                tint: model.goalMet ? Color.success : Color.brand,
                label: "\(Int((progress * 100).rounded()))%"
            )
            .frame(width: 92, height: 92)
            .overlay {
                if model.goalMet {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.success)
                        .offset(y: 46)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Daily goal")
            .accessibilityValue("\(model.xpToday) of \(model.xpGoal) XP, \(model.goalMet ? "met" : "in progress")")

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(model.goalMet ? "Goal met" : "Daily goal")
                    .font(AppFont.display(.headline, weight: .semibold))
                    .foregroundStyle(model.goalMet ? Color.success : Color.primary)

                if model.goalMet {
                    // Deliberately not celebratory: the goal is met, the day is
                    // not over, and a trophy here would cry wolf every evening.
                    Text("\(model.xpToday) XP today, \(model.xpRemaining) over target. Anything more is bonus.")
                        .font(AppFont.display(.subheadline, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(model.xpRemaining) XP to go.")
                        .font(AppFont.display(.subheadline, weight: .regular))
                        .foregroundStyle(.secondary)

                    Text(remainingHint)
                        .font(AppFont.display(.caption, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
        .cardStyle()
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8), value: progress)
    }

    /// No estimate when there is no rate to estimate from. Saying "5 min left"
    /// with no data behind it would be a decoration, not a fact.
    private var remainingHint: String {
        guard let minutes = model.minutesRemaining else {
            return model.todayMinutes == 0
                ? "No study time logged yet today."
                : "Rate unknown for today."
        }
        return minutes == 1 ? "About a minute at today's pace." : "About \(minutes) min at today's pace."
    }
}

// MARK: - Vocabulary review

/// How many words are due, and the route into reviewing them.
struct VocabularyReviewCard: View {

    let model: HomeModel
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HomeSectionHeader(
                title: "Vocabulary review",
                subtitle: model.dueWordCount > 0 ? "Spaced repetition, due now" : "Nothing due"
            )

            if model.dueWordCount > 0 {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "character.book.closed.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.brand)
                        .accessibilityHidden(true)

                    Text("\(model.dueWordCount) word\(model.dueWordCount == 1 ? "" : "s") due")
                        .font(AppFont.display(.title3, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }

                PrimaryButton(
                    title: "Review \(model.dueWordCount) word\(model.dueWordCount == 1 ? "" : "s")",
                    symbol: "arrow.triangle.2.circlepath"
                ) {
                    onReview()
                }
                .accessibilityHint("Starts a spaced repetition session")
            } else {
                // Empty state that reads as good news, not as missing content.
                EmptyStateView(
                    symbol: "checkmark.circle",
                    title: "All caught up",
                    message: "No words are due right now. Words you have studied will come back here on schedule.",
                    actionTitle: nil,
                    action: nil
                )
            }
        }
    }
}

// MARK: - Weak topics

/// The three weakest topics, each with the evidence.
struct WeakTopicsCard: View {

    let model: HomeModel
    let onPractise: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HomeSectionHeader(
                title: "Weak topics",
                subtitle: model.weakTopics.isEmpty ? nil : "Lowest accuracy first"
            )

            if model.weakTopics.isEmpty {
                EmptyStateView(
                    symbol: "chart.bar.xaxis",
                    title: "Not enough attempts yet",
                    message: "After a few exercises per topic your three weakest areas appear here, each with the numbers behind them.",
                    actionTitle: nil,
                    action: nil
                )
                .cardStyle()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.weakTopics.enumerated()), id: \.element.topicID) { index, topic in
                        Button {
                            onPractise(topic.topicID)
                        } label: {
                            row(for: topic)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens practice for \(topic.title)")

                        if index < model.weakTopics.count - 1 {
                            Divider().padding(.leading, Spacing.lg + 48)
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)
                .cardStyle()
            }
        }
    }

    private func row(for topic: HomeModel.WeakTopic) -> some View {
        HStack(spacing: Spacing.md) {
            ProgressRing(
                progress: topic.accuracy,
                lineWidth: 4,
                tint: topic.accuracy < 0.5 ? Color.danger : Color.warning,
                label: "\(Int((topic.accuracy * 100).rounded()))"
            )
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                    .font(AppFont.display(.body, weight: .medium))
                    .foregroundStyle(.primary)
                Text(topic.explanation)
                    .font(AppFont.display(.caption, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(topic.title), \(Int((topic.accuracy * 100).rounded())) percent accuracy. \(topic.explanation)")
    }
}

// MARK: - Recommended practice

/// One concrete next action, generated from whatever data exists.
struct RecommendedPracticeCard: View {

    let model: HomeModel
    let onPerform: (HomeModel.RecommendedAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HomeSectionHeader(title: "Recommended practice", subtitle: "One thing to do next")

            if let rec = model.recommendedPractice {
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: rec.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.brand)
                        .frame(width: 30)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(rec.title)
                            .font(AppFont.display(.headline, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)

                        Text(rec.detail)
                            .font(AppFont.display(.subheadline, weight: .regular))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                PrimaryButton(title: rec.actionTitle, symbol: "arrow.right") {
                    onPerform(rec.action)
                }
            } else {
                EmptyStateView(
                    symbol: "sparkles",
                    title: "Nothing to suggest",
                    message: "The course has no lessons and no progress to act on. Add content and this section fills itself.",
                    actionTitle: nil,
                    action: nil
                )
            }
        }
        .padding(Spacing.lg)
        .cardStyle()
    }
}

// MARK: - IELTS

/// A doorway into the IELTS tab, with the real state of the papers.
struct IELTSCard: View {

    let model: HomeModel
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HomeSectionHeader(title: "IELTS practice", subtitle: nil)

            HStack(spacing: Spacing.md) {
                Image(systemName: "globe")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.ieltsModulesDone) of \(model.ieltsModulesTotal) papers started")
                        .font(AppFont.display(.headline, weight: .semibold))

                    if let detail = model.ieltsFocusDetail {
                        Text(detail)
                            .font(AppFont.display(.caption, weight: .regular))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No IELTS modules in this course yet.")
                            .font(AppFont.display(.caption, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            if let band = model.ieltsBandFocus {
                HStack(spacing: Spacing.xs) {
                    LevelPill(text: "Target band \(band)")
                }
            }

            if model.ieltsModulesTotal > 0 {
                PrimaryButton(title: "Open IELTS", symbol: "arrow.right") { onOpen() }
                    .accessibilityHint("Switches to the IELTS tab")
            } else {
                EmptyStateView(
                    symbol: "globe",
                    title: "No papers bundled",
                    message: "IELTS modules ship with the course content. None are loaded in this build.",
                    actionTitle: nil,
                    action: nil
                )
            }
        }
        .padding(Spacing.lg)
        .cardStyle()
    }
}
