import EnglishCore
import SwiftUI

/// Reading lessons: the passage in a comfortable, resizable column first, then the
/// questions, then the same review screen listening gets.
///
/// The passage is collapsible so a learner revising a mistake does not have to scroll
/// past two thousand words to reach the question they are working on.
struct ReadingLessonView: View {
    let lesson: IELTSPaperLesson

    @Environment(AppState.self) private var appState

    @State private var phase: Phase = .attempt
    @State private var session: LearnSession?
    @State private var passageCollapsed = false

    private enum Phase: Equatable { case attempt, review }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                lessonHeader

                if !lesson.passage.isEmpty {
                    passageSection
                }

                switch phase {
                case .attempt: attemptBody
                case .review:
                    LessonReviewScreen(
                        lesson: lesson,
                        session: session,
                        showTranscript: false
                    )
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.examPaper.ignoresSafeArea())
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prepare)
    }

    // MARK: Header

    private var lessonHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(lesson.title)
                .font(.examDisplay(24))
                .foregroundStyle(Color.examInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.xs) {
                if let band = lesson.band {
                    LevelPill(text: "Target \(band)")
                        .accessibilityLabel("Target band of this material, \(band)")
                }
                LevelPill(text: "\(lesson.questionCount) questions")
                LevelPill(text: "\(lesson.targetMinutes) min")
            }
            Text("Self-authored passage. Not official IELTS™ material.")
                .font(.examBody(11))
                .foregroundStyle(Color.examInkSoft.opacity(0.8))
        }
    }

    // MARK: Passage

    private var passageSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                withAnimation(ExamMotion.reveal) { passageCollapsed.toggle() }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: passageCollapsed ? "chevron.right" : "chevron.down")
                        .font(.examBody(12, weight: .bold))
                        .foregroundStyle(Color.examRed)
                    Text(passageCollapsed ? "Show the passage" : "Hide the passage")
                        .font(.examBody(13, weight: .medium))
                        .foregroundStyle(Color.examRed)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(passageCollapsed ? "Shows the full passage again" : "Collapses the passage so you can reach the questions")

            if !passageCollapsed {
                ReadingColumnView(paragraphs: lesson.passage)
            }
        }
    }

    // MARK: Attempt

    @ViewBuilder
    private var attemptBody: some View {
        if let session {
            VStack(alignment: .leading, spacing: Spacing.md) {
                QuestionNavigator(
                    groups: lesson.groups,
                    currentNumber: currentNumber(in: session),
                    answered: answered(in: session),
                    onJump: { jump(to: $0, in: session) }
                )

                if let current = session.current?.asExercise {
                    ExerciseView(
                        exercise: current,
                        topicID: "ielts",
                        onComplete: { _ in advance(session) }
                    )
                } else if session.isFinished {
                    PrimaryButton(title: "See the review", symbol: "checkmark") {
                        phase = .review
                        appState.store.completeLesson(lesson.id, topicID: "ielts", xp: 0)
                        Haptics.success()
                    }
                }
            }
        }
    }

    // MARK: Session plumbing

    private func prepare() {
        guard session == nil, !lesson.questions.isEmpty else { return }
        session = LearnSession(items: lesson.questions.map { .exercise($0.exercise) })
    }

    private func currentNumber(in session: LearnSession) -> Int? {
        guard let id = session.current?.asExercise?.id else { return nil }
        return lesson.questions.first { $0.exercise.id == id }?.number
    }

    private func answered(in session: LearnSession) -> Set<Int> {
        let done = Set(session.results.map(\.exerciseID))
        return Set(lesson.questions.filter { done.contains($0.exercise.id) }.map(\.number))
    }

    private func jump(to number: Int, in session: LearnSession) {
        guard let target = lesson.questions.first(where: { $0.number == number }),
              let index = session.items.firstIndex(where: { $0.asExercise?.id == target.exercise.id })
        else { return }
        if index < session.index {
            session.index = index
        } else {
            while session.index < index && !session.isFinished { _ = session.next() }
        }
        Haptics.selection()
    }

    private func advance(_ session: LearnSession) {
        if !session.next() {
            phase = .review
            Haptics.success()
        }
    }
}

/// One row per lesson in the reading paper.
struct ReadingSectionView: View {
    let paper: IELTSPaper

    var body: some View {
        List {
            Section {
                ForEach(paper.lessons) { lesson in
                    NavigationLink {
                        ReadingLessonView(lesson: lesson)
                    } label: {
                        LessonRow(lesson: lesson, skill: .reading)
                            .padding(.vertical, Spacing.xs)
                    }
                    .listRowBackground(Color.examPaper)
                    .listRowSeparatorTint(Color.examRule)
                }
            } header: {
                Text(paper.title)
                    .font(.examBody(12, weight: .semibold))
                    .foregroundStyle(Color.examInkSoft)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.examPaper)
        .navigationTitle("Reading")
        .navigationBarTitleDisplayMode(.inline)
    }
}