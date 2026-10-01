import EnglishCore
import EnglishStore
import SwiftUI

/// The IELTS tab root: four papers, a segmented switch between them, an honest
/// orientation note, and a "next up" that points at whichever skill has had the
/// least attention.
struct IELTSHomeView: View {
    @Environment(AppState.self) private var appState

    /// `nil` until the library is loaded; ``refresh(library:)`` fills it in.
    @State private var model = IELTSSectionModel(library: nil)
    @State private var selectedSkill: IELTSSkill = .listening
    @State private var hasAppeared = false

    var body: some View {
        @Bindable var state = appState

        NavigationStack(path: $state.navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header
                    ProgressOverview(model: model)
                    orientationCard
                    paperSwitcher
                    skillContent
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.examPaper.ignoresSafeArea())
            .navigationTitle("IELTS")
            .navigationBarTitleDisplayMode(.large)
        }
        .readsReduceMotion()
        .onAppear { hasAppeared = true }
        // Content can finish loading after the first render, so re-derive rather
        // than reading the library once in the initialiser.
        .onChange(of: appState.library?.allIELTSModules.count) { _, _ in
            model.refresh(library: appState.library)
        }
        .task {
            model.refresh(library: appState.library)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Practise all four papers")
                .font(.examDisplay(30))
                .foregroundStyle(Color.examInk)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(model.totalLessons) lessons · \(totalMinutes) minutes of material")
                .font(.examBody(14))
                .foregroundStyle(Color.examInkSoft)
        }
        .padding(.top, Spacing.sm)
        .accessibilityElement(children: .combine)
        .examReveal(hasAppeared, delay: 0.05)
    }

    private var totalMinutes: Int {
        model.skillOrder.reduce(0) { $0 + model.totalMinutes(for: $1) }
    }

    // MARK: - Orientation

    private var orientationCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label(ExamCopy.disclaimerTitle, systemImage: "info.circle")
                .font(.examBody(15, weight: .semibold))
                .foregroundStyle(Color.examInk)
            Text(ExamCopy.disclaimerBody)
                .font(.examBody(14))
                .foregroundStyle(Color.examInkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .examPage()
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.examRed)
                .frame(width: 3)
                .padding(.vertical, 22)
        }
        .accessibilityElement(children: .combine)
        .examReveal(hasAppeared, delay: 0.12)
    }

    // MARK: - Paper switcher

    private var paperSwitcher: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Papers", subtitle: "Listening · Reading · Writing · Speaking")
            Picker("Paper", selection: $selectedSkill) {
                ForEach(model.skillOrder, id: \.self) { skill in
                    Text(shortTitle(for: skill)).tag(skill)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("IELTS paper")
            .accessibilityHint("Switches which paper's lessons are listed below")

            nextUpCard
        }
        .examReveal(hasAppeared, delay: 0.2)
    }

    private func shortTitle(for skill: IELTSSkill) -> String {
        switch skill {
        case .listening: return "Listen"
        case .reading: return "Read"
        case .writing: return "Write"
        case .speaking: return "Speak"
        }
    }

    // MARK: - Next up

    @ViewBuilder
    private var nextUpCard: some View {
        let totals = SkillTime.totals(store: appState.store, model: model)
        if let least = model.leastPractised(using: totals) {
            let minutes = totals[least] ?? 0
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: symbol(for: least))
                    .font(.examBody(17, weight: .semibold))
                    .foregroundStyle(Color.examTeal)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next up: \(IELTSPaperLesson.skillName(least))")
                        .font(.examBody(15, weight: .semibold))
                        .foregroundStyle(Color.examInk)
                    Text(minutes == 0
                         ? "You have not spent any time on this paper yet."
                         : "Your least-practised paper so far, at \(minutes) min.")
                        .font(.examBody(13))
                        .foregroundStyle(Color.examInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if let target = nextLesson(for: least) {
                        NavigationLink {
                            LessonDestination.destination(for: target)
                        } label: {
                            HStack(spacing: 4) {
                                Text(target.title)
                                    .font(.examBody(14, weight: .medium))
                                Image(systemName: "arrow.right")
                                    .font(.examBody(11, weight: .bold))
                            }
                            .foregroundStyle(Color.examRed)
                        }
                        .padding(.top, 2)
                        .accessibilityHint("Opens the next unfinished lesson in \(IELTSPaperLesson.skillName(least))")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.sm)
            .background(Color.examPaperSunk, in: .rect(cornerRadius: Radius.card))
        }
    }

    private func nextLesson(for skill: IELTSSkill) -> IELTSPaperLesson? {
        let rows = appState.store.lessonProgress()
        return model.lessons(for: skill).first { rows[$0.id]?.completed != true }
            ?? model.lessons(for: skill).first
    }

    // MARK: - Per-paper content

    @ViewBuilder
    private var skillContent: some View {
        let lessons = model.lessons(for: selectedSkill)
        if lessons.isEmpty {
            EmptyStateView(
                symbol: "questionmark.folder",
                title: "Nothing loaded for this paper",
                message: model.loadWarning ?? "No lessons were found for \(IELTSPaperLesson.skillName(selectedSkill)).",
                actionTitle: nil,
                action: nil
            )
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: Spacing.md) {
                SectionHeader(
                    title: model.paper(for: selectedSkill)?.title ?? "Lessons",
                    subtitle: "\(lessons.count) lessons · \(model.totalMinutes(for: selectedSkill)) min"
                )
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(lessons) { lesson in
                        NavigationLink {
                            LessonDestination.destination(for: lesson)
                        } label: {
                            LessonRow(lesson: lesson, skill: selectedSkill)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func symbol(for skill: IELTSSkill) -> String {
        switch skill {
        case .listening: return "waveform"
        case .reading: return "text.book.closed"
        case .writing: return "square.and.pencil"
        case .speaking: return "bubble.left.and.bubble.right"
        }
    }
}

// MARK: - One lesson row

/// Title, target band, minutes, question count, completion, and resume state.
/// The two numbers are never conflated: the band is the material's level, the
/// progress ring is practice progress.
struct LessonRow: View {
    let lesson: IELTSPaperLesson
    let skill: IELTSSkill
    @Environment(AppState.self) private var appState

    private var snapshot: ProgressSnapshot {
        guard let row = appState.store.lessonProgress()[lesson.id] else {
            return ProgressSnapshot(isCompleted: false, currentStepIndex: 0, updatedAt: nil)
        }
        return ProgressSnapshot(
            isCompleted: row.completed,
            currentStepIndex: row.currentStepIndex,
            updatedAt: row.updatedAt
        )
    }

    private var fraction: Double {
        guard lesson.questionCount > 0 else { return 0 }
        return min(Double(snapshot.currentStepIndex) / Double(lesson.questionCount), 1)
    }

    var body: some View {
        let progress = snapshot
        HStack(spacing: Spacing.md) {
            ProgressRing(
                progress: fraction,
                lineWidth: 4,
                tint: progress.isCompleted ? Color.examCorrect : Color.examRed,
                label: progress.isCompleted ? "Done" : "\(Int(fraction * 100))%"
            )
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                Text(lesson.title)
                    .font(.examBody(16, weight: .semibold))
                    .foregroundStyle(Color.examInk)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Spacing.xs) {
                    if let band = lesson.band {
                        LevelPill(text: "Target \(band)")
                            .accessibilityLabel("Target band of this material, \(band)")
                    }
                    metaPill("\(lesson.targetMinutes) min", symbol: "clock")
                    metaPill("\(lesson.questionCount) \(lesson.isWritingOrSpeaking ? "items" : "questions")", symbol: "list.number")
                    if lesson.hasTranscript { metaPill("Transcript", symbol: "text.quote") }
                    if !lesson.passage.isEmpty { metaPill("Passage", symbol: "doc.plaintext") }
                }
            }

            Spacer(minLength: Spacing.xs)

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(progress.resumeLabel)
                    .font(.examBody(12, weight: .semibold))
                    .foregroundStyle(progress.isStarted ? Color.examRed : Color.examInkSoft)
                Image(systemName: "chevron.right")
                    .font(.examBody(11, weight: .bold))
                    .foregroundStyle(Color.examInkSoft.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .examPage(padding: Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(progress.isCompleted ? "Opens this lesson for review" : "Opens this lesson")
        .overlay(alignment: .topTrailing) {
            if progress.isCompleted {
                Image(systemName: "checkmark.seal.fill")
                    .font(.examBody(13))
                    .foregroundStyle(Color.examCorrect)
                    .padding(10)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func metaPill(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.examBody(11))
            .foregroundStyle(Color.examInkSoft)
            .labelStyle(.titleAndIcon)
            .accessibilityHidden(true)
    }

    private var accessibilitySummary: String {
        var parts = [lesson.title]
        if let band = lesson.band { parts.append("target band \(band)") }
        parts.append("\(lesson.targetMinutes) minutes")
        parts.append("\(lesson.questionCount) questions")
        parts.append(snapshot.resumeLabel)
        return parts.joined(separator: ", ")
    }
}

// MARK: - Progress overview

/// Lessons completed per skill, total minutes practised, and the target band of
/// whatever is in front of the learner. Never presented as an IELTS grade.
struct ProgressOverview: View {
    let model: IELTSSectionModel
    @Environment(AppState.self) private var appState

    var body: some View {
        let rows = appState.store.lessonProgress()
        let stats = appState.store.learnerStats()
        let done = model.papers.lazy.flatMap(\.lessons).filter { rows[$0.id]?.completed == true }.count

        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Your practice", subtitle: "What you have covered so far")

            HStack(spacing: Spacing.sm) {
                StatCard(
                    title: "Lessons done",
                    value: "\(done)",
                    caption: "of \(model.totalLessons)",
                    symbol: "checkmark.circle",
                    tint: .examCorrect
                )
                StatCard(
                    title: "Time practised",
                    value: Self.formattedMinutes(stats.studyMinutes),
                    caption: "in the app",
                    symbol: "clock",
                    tint: .examTeal
                )
            }

            VStack(spacing: 6) {
                ForEach(model.skillOrder, id: \.self) { skill in
                    SkillProgressLine(
                        skill: skill,
                        completed: model.lessons(for: skill).filter { rows[$0.id]?.completed == true }.count,
                        total: model.lessons(for: skill).count
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.sm)
    }

    static func formattedMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(rest)m"
    }
}

private struct SkillProgressLine: View {
    let skill: IELTSSkill
    let completed: Int
    let total: Int

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(IELTSPaperLesson.skillName(skill))
                .font(.examBody(13, weight: .medium))
                .foregroundStyle(Color.examInk)
                .frame(width: 74, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.examRule.opacity(0.6))
                    Capsule()
                        .fill(Color.examRed.opacity(0.85))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 6)

            Text("\(completed)/\(total)")
                .font(.examMono(11, weight: .medium))
                .foregroundStyle(Color.examInkSoft)
                .frame(width: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(IELTSPaperLesson.skillName(skill)), \(completed) of \(total) lessons complete")
    }

    private var fraction: Double {
        total == 0 ? 0 : Double(completed) / Double(total)
    }
}

// MARK: - Where the practice minutes came from

/// Minutes per paper, derived from completed lessons only.
///
/// The store keeps total study time but does not break it down per paper, so a minute
/// that cannot be attributed is left out rather than guessed. That makes the
/// "least-practised" recommendation conservative: it can only be wrong by
/// under-counting somebody who practised a paper without finishing a lesson.
enum SkillTime {
    @MainActor static func totals(store: ProgressStore, model: IELTSSectionModel) -> [IELTSSkill: Int] {
        let rows = store.lessonProgress()
        var totals: [IELTSSkill: Int] = [:]
        for paper in model.papers {
            for lesson in paper.lessons where rows[lesson.id]?.completed == true {
                totals[lesson.skill, default: 0] += lesson.targetMinutes
            }
        }
        return totals
    }
}

// MARK: - Where a lesson opens

/// Routes a lesson to the screen its skill needs. One place, so the home rows,
/// the "next up" link, and any future deep link cannot drift apart.
enum LessonDestination {
    @ViewBuilder
    static func destination(for lesson: IELTSPaperLesson) -> some View {
        switch lesson.skill {
        case .listening: ListeningLessonView(lesson: lesson)
        case .reading: ReadingLessonView(lesson: lesson)
        case .writing: WritingTaskView(lesson: lesson)
        case .speaking: IELTSSpeakingLessonView(lesson: lesson)
        }
    }
}

extension IELTSPaperLesson {
    var isWritingOrSpeaking: Bool { skill == .writing || skill == .speaking }
}