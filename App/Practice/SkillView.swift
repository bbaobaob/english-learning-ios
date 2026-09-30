import SwiftUI
import EnglishCore
import EnglishStore

/// One screen for all four skills: level picker, the three lessons, a mixed practice
/// set per level, the progress rollup, and a shortcut into the review queue filtered
/// to this skill.
///
/// The lesson player belongs to `App/Learn`, and grading belongs to `ExerciseView` /
/// `LearnSession`. This screen composes them; it does not re-implement either.
///
/// // TODO(learn-lane): `LessonView(topicID:lessonID:)` is the assumed entry point into
/// App/Learn. If that screen lands under a different name, this is the only line to
// change — the mixed-practice and dictation paths below never touch it.
struct SkillView: View {

    let topicID: String
    let skill: CoreSkill

    @Environment(AppState.self) private var appState

    @State private var level: Level = .beginner
    @State private var showPractice = false
    @State private var showReview = false

    /// This skill's topic, when the library has loaded it.
    private var topic: Topic? { appState.library?.topic(topicID) }

    var body: some View {
        Group {
            if let topic {
                content(topic)
            } else {
                EmptyStateView(
                    symbol: skill.fallbackSymbol,
                    title: "Topic unavailable",
                    message: "This skill's content could not be loaded.",
                    actionTitle: nil,
                    action: nil
                )
            }
        }
        .navigationTitle(topic?.title ?? skill.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showReview) {
            ReviewView(topicID: topicID)
        }
    }

    // MARK: - Content

    private func content(_ topic: Topic) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                promiseCard(topic)
                levelPicker(topic)
                practiceAction(topic)
                lessonsSection(topic)
                progressSection(topic)
                mistakesSection(topic)
                reviewAction(topic)
                Color.clear.frame(height: Spacing.xl)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
        }
        .background(PracticeBackdrop())
        .task(id: topic.id) {
            // Open on the level the learner has already reached, falling back to the
            // topic's own level. Purely a starting point, not a grade.
            level = firstLevelTouched(topic) ?? topic.level
        }
    }

    private func promiseCard(_ topic: Topic) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Image(systemName: topic.icon.isEmpty ? skill.fallbackSymbol : topic.icon).font(AppFont.body(.largeTitle))
                    .foregroundStyle(Color.brand)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.title)
                        .font(AppFont.display(24, .bold))
                        .accessibilityAddTraits(.isHeader)
                    LevelPill(text: topic.level.displayName)
                }
                Spacer(minLength: 0)
            }

            Text(topic.summary.isEmpty ? skill.promise : topic.summary)
                .font(AppFont.display(15, .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(skill.promise)
                .font(AppFont.display(13, .semibold))
                .foregroundStyle(Color.brand)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func levelPicker(_ topic: Topic) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(
                title: "Level",
                subtitle: "Each level has its own lesson and its own mixed set",
                actionTitle: nil,
                action: nil
            )

            Picker("Level", selection: $level) {
                ForEach(Level.studyOrder, id: \.self) { candidate in
                    Text(candidate.displayName).tag(candidate)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: level) { _, _ in Haptics.selection() }
            .accessibilityHint("Changes which lesson and which practice set are shown")

            let lessonCount = topic.lessons(at: level).count
            Text(lessonCount == 0
                 ? "This level has no lesson yet."
                 : PracticeFormat.phrase(lessonCount, "lesson", "lessons") + " at this level")
                .font(AppFont.display(13, .regular))
                .foregroundStyle(.secondary)
        }
    }

    private func practiceAction(_ topic: Topic) -> some View {
        let count = topic.exercises(at: level).count

        return VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(
                title: "Practice",
                subtitle: "Every \(level.displayName.lowercased()) exercise in this skill, mixed together",
                actionTitle: nil,
                action: nil
            )

            if count == 0 {
                EmptyStateView(
                    symbol: "tray",
                    title: "No \(level.displayName.lowercased()) exercises",
                    message: "This level teaches only, so there is nothing to drill yet.",
                    actionTitle: nil,
                    action: nil
                )
            } else {
                PrimaryButton(
                    title: "Practise \(PracticeFormat.phrase(count, "exercise", "exercises"))",
                    symbol: "play.fill",
                    isEnabled: true,
                    action: {
                        Haptics.selection()
                        showPractice = true
                    }
                )
                .navigationDestination(isPresented: $showPractice) {
                    MixedPracticeView(topicID: topic.id, skill: skill, level: level)
                }
            }
        }
    }

    private func lessonsSection(_ topic: Topic) -> some View {
        let lessonRows = appState.store.lessonProgress()
        let levels = Level.studyOrder.filter { !topic.lessons(at: $0).isEmpty }

        return VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(
                title: "Lessons",
                subtitle: "Read it, hear it, then practise it",
                actionTitle: nil,
                action: nil
            )

            ForEach(levels, id: \.self) { lessonLevel in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    LevelPill(text: lessonLevel.displayName)

                    ForEach(topic.lessons(at: lessonLevel)) { lesson in
                        lessonRow(lesson, rows: lessonRows, topic: topic)
                    }
                }
            }
        }
    }

    private func lessonRow(_ lesson: Lesson, rows: [String: LessonProgress], topic: Topic) -> some View {
        let row = rows[lesson.id]
        let state = LessonState(row: row, lesson: lesson)

        return NavigationLink {
            LessonView(topicID: topic.id, lessonID: lesson.id)
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: state.symbol).font(AppFont.body(.title3))
                    .foregroundStyle(state.tint)
                    .frame(width: 30)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(lesson.title)
                        .font(AppFont.display(16, .semibold))
                        .multilineTextAlignment(.leading)
                    Text(lesson.summary)
                        .font(AppFont.display(13, .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(state.caption)
                        .font(AppFont.mono(12, .semibold))
                        .foregroundStyle(state.tint)
                }

                Spacer(minLength: Spacing.xs)

                Image(systemName: "chevron.right").font(AppFont.body(.footnote, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(state.caption)
        .accessibilityHint("Opens the lesson")
    }

    private func progressSection(_ topic: Topic) -> some View {
        let rollup = appState.store.topicProgress()[topic.id]
        let completion = topic.lessonCompletion(appState.store.lessonProgress())
        let dictationCount = topic.dictationItems.count

        return VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(
                title: "Progress",
                subtitle: "Lesson completion per level, and how accurate you are",
                actionTitle: nil,
                action: nil
            )

            HStack(spacing: Spacing.md) {
                ForEach(Level.studyOrder, id: \.self) { candidate in
                    let ring = levelProgress(candidate, in: topic)
                    VStack(spacing: Spacing.xs) {
                        ProgressRing(
                            progress: ring.progress,
                            lineWidth: 8,
                            tint: ring.tint,
                            label: candidate.displayName
                        )
                        Text(ring.caption)
                            .font(AppFont.display(12, .regular))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(ring.caption)
                }
            }

            PracticeMeter(
                title: "Overall accuracy",
                caption: rollup.map {
                    PracticeFormat.count($0.exercisesDone) + " exercises · "
                        + PracticeFormat.count($0.correctCount) + " correct"
                } ?? "No exercises graded yet",
                value: rollup?.accuracy ?? 0,
                tint: .accuracy
            )
            .padding(Spacing.lg)
            .cardStyle()

            HStack(spacing: Spacing.md) {
                StatCard(
                    title: "Lessons",
                    value: PracticeFormat.percent(completion),
                    caption: "\(topic.lessons.count) in this skill",
                    symbol: "book.pages",
                    tint: .brand
                )
                StatCard(
                    title: "Dictation",
                    value: PracticeFormat.count(dictationCount),
                    caption: "sentences to write",
                    symbol: "keyboard",
                    tint: .brandSoft
                )
            }
        }
    }

    private func mistakesSection(_ topic: Topic) -> some View {
        let mistakes = appState.store.reviewQueue(on: Date()).filter { $0.topicID == topic.id }

        return VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(
                title: "Your mistakes",
                subtitle: "Everything the scheduler still wants you to see in this skill",
                actionTitle: nil,
                action: nil
            )

            if mistakes.isEmpty {
                EmptyStateView(
                    symbol: "checkmark.seal",
                    title: hasAnyProgress(topic) ? "Nothing outstanding" : "No mistakes yet",
                    message: hasAnyProgress(topic)
                        ? "Everything in this skill is scheduled for later. Check back when it is due."
                        : "Answer a few exercises and anything you get wrong will be listed here.",
                    actionTitle: nil,
                    action: nil
                )
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(mistakes.prefix(6)) { item in
                        Button {
                            Haptics.selection()
                            showReview = true
                        } label: {
                            ReviewItemRow(
                                item: item,
                                headline: headline(for: item),
                                detail: "Due \(item.dueDate.formatted(date: .abbreviated, time: .omitted))"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens this skill's review queue")
                    }
                }

                if mistakes.count > 6 {
                    Text("and \(mistakes.count - 6) more")
                        .font(AppFont.display(13, .regular))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func reviewAction(_ topic: Topic) -> some View {
        let due = appState.store.reviewQueue(on: Date()).filter { $0.topicID == topic.id }.count

        return VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(
                title: "Review",
                subtitle: "The spaced repetition queue, filtered to \(topic.title)",
                actionTitle: nil,
                action: nil
            )

            if due == 0 {
                EmptyStateView(
                    symbol: "tray",
                    title: "Nothing due in this skill",
                    message: "The scheduler has nothing outstanding for \(topic.title) right now.",
                    actionTitle: nil,
                    action: nil
                )
            } else {
                PrimaryButton(
                    title: "Review \(PracticeFormat.phrase(due, "item", "items"))",
                    symbol: "arrow.triangle.2.circlepath",
                    isEnabled: true,
                    action: { showReview = true }
                )
            }
        }
    }

    // MARK: - Reads

    /// The level the learner has already finished a lesson at, or touched, if any.
    private func firstLevelTouched(_ topic: Topic) -> Level? {
        let rows = appState.store.lessonProgress()
        for candidate in Level.studyOrder {
            if topic.lessons(at: candidate).contains(where: { rows[$0.id] != nil }) {
                return candidate
            }
        }
        return nil
    }

    private func levelProgress(_ candidate: Level, in topic: Topic) -> (progress: Double, caption: String, tint: Color) {        let rows = appState.store.lessonProgress()
        let lessons = topic.lessons(at: candidate)
        guard !lessons.isEmpty else {
            return (0, "Not offered", .secondary)
        }
        let done = lessons.filter { rows[$0.id]?.completed == true }.count
        let progress = Double(done) / Double(lessons.count)
        let tint: Color = done == lessons.count ? .success : (done > 0 ? .brand : .brandSoft)
        return (progress, "\(done) of \(lessons.count) done", tint)
    }

    private func hasAnyProgress(_ topic: Topic) -> Bool {
        (appState.store.topicProgress()[topic.id]?.exercisesDone ?? 0) > 0
    }

    private func headline(for item: ReviewItem) -> String {
        switch item.source {
        case .exercise:
            appState.library?.exercise(item.refID)?.prompt ?? item.refID
        case .vocabulary:
            appState.library?.vocabWord(item.refID)?.word ?? item.refID
        case .lesson:
            appState.library?.lesson(item.refID)?.title ?? item.refID
        }
    }
}

/// Where a lesson row should point the learner.
struct LessonState {
    let row: LessonProgress?
    let lesson: Lesson

    init(row: LessonProgress?, lesson: Lesson) {
        self.row = row
        self.lesson = lesson
    }

    var isCompleted: Bool { row?.completed == true }

    var isStarted: Bool { (row?.currentStepIndex ?? 0) > 0 && !isCompleted }

    var symbol: String {
        if isCompleted { return "checkmark.circle.fill" }
        if isStarted { return "arrow.triangle.2.circlepath" }
        return "play.circle"
    }

    var tint: Color {
        if isCompleted { return .success }
        if isStarted { return .warning }
        return .brand
    }

    var caption: String {
        if isCompleted { return "Completed · +\(lesson.xp) XP" }
        if isStarted {
            let step = min((row?.currentStepIndex ?? 0) + 1, lesson.steps.count)
            return "Resume · step \(step) of \(lesson.steps.count)"
        }
        return "Not started · \(PracticeFormat.phrase(lesson.steps.count, "step", "steps"))"
    }
}
