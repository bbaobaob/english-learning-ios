import EnglishCore
import SwiftUI

/// Listening lessons. One row per lesson in a paper, then the attempt.
///
/// The rule this screen exists to enforce: **the transcript is not in the attempt.**
/// The only transcript affordance during an attempt is behind a confirmation that
/// says what it costs you.
struct ListeningSectionView: View {
    let paper: IELTSPaper
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section {
                ForEach(paper.lessons) { lesson in
                    NavigationLink {
                        ListeningLessonView(lesson: lesson)
                    } label: {
                        LessonRow(lesson: lesson, skill: .listening)
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
        .navigationTitle("Listening")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - The attempt

/// One listening lesson: play the audio once, answer every question, then review.
///
/// The transcript lives in `TranscriptPanelView`, which stays sealed until the
/// session finishes — or until the learner explicitly breaks the seal.
struct ListeningLessonView: View {
    let lesson: IELTSPaperLesson

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .attempt
    @State private var session: LearnSession?
    @State private var confirmReveal = false
    /// The learner chose to see the transcript mid-attempt. Sticky, and named out loud.
    @State private var transcriptBroken = false

    private enum Phase: Equatable {
        case attempt
        case review
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                lessonHeader

                switch phase {
                case .attempt: attemptBody
                case .review:
                    LessonReviewScreen(
                        lesson: lesson,
                        session: session,
                        showTranscript: lesson.hasTranscript
                    )
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.examPaper.ignoresSafeArea())
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Show the transcript now?",
            isPresented: $confirmReveal,
            titleVisibility: .visible,
            presenting: lesson
        ) { _ in
            Button("Show transcript", role: .destructive) { transcriptBroken = true }
            Button("Keep it sealed", role: .cancel) {}
        } message: { _ in
            Text("This attempt no longer measures listening. You can still finish, but the transcript will stay on screen and you will not be able to un-see it.")
        }
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

            Text("Self-authored practice. Not official IELTS™ material.")
                .font(.examBody(11))
                .foregroundStyle(Color.examInkSoft.opacity(0.8))
        }
    }

    // MARK: Attempt

    @ViewBuilder
    private var attemptBody: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let audio = lesson.audio {
                audioCard(audio)
            }

            if let session {
                QuestionNavigator(
                    groups: lesson.groups,
                    currentNumber: currentQuestionNumber(in: session),
                    answered: answeredNumbers(in: session),
                    onJump: { number in jump(to: number, in: session) }
                )

                if let current = session.current?.exercise {
                    // TODO(exercise-lane): confirm the exact ExerciseView signature.
                    // Expected: an exercises array plus a completion action.
                    ExerciseView(
                        exercise: current,
                        topicID: "ielts",
                        onComplete: { _ in advance(session) }
                    )
                } else if session.isFinished {
                    finishButton
                }

                if transcriptBroken && lesson.hasTranscript {
                    TranscriptPanelView(lesson: lesson, isSealed: false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if lesson.hasTranscript {
                    sealedTranscriptCard
                }
            }
        }
        .animation(ExamMotion.reveal, value: transcriptBroken)
    }

    private func audioCard(_ audio: AudioClip) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "The recording", subtitle: "Play it once, as in the test")
            // TODO(audio-lane): swap for the shared audio player when it lands.
            AudioPlayerCard(clip: audio)
                .accessibilityLabel("Recording for \(lesson.title)")
        }
        .examPage()
    }

    private var sealedTranscriptCard: some View {
        Button {
            confirmReveal = true
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "lock.fill")
                    .font(.examBody(14))
                    .foregroundStyle(Color.examInkSoft)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Transcript sealed")
                        .font(.examBody(14, weight: .semibold))
                        .foregroundStyle(Color.examInk)
                    Text("Available once you submit. Opening it now is allowed, but it ends the point of the exercise.")
                        .font(.examBody(12))
                        .foregroundStyle(Color.examInkSoft)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Transcript, sealed until you submit")
        .accessibilityHint("Double tap to open a confirmation asking whether you want to see it now")
    }

    private var finishButton: some View {
        PrimaryButton(title: "See the review", symbol: "checkmark") {
            phase = .review
            appState.store.completeLesson(lesson.id, topicID: "ielts", xp: 0)
            Haptics.success()
        }
        .accessibilityHint("Ends the attempt and opens the question-by-question review")
    }

    // MARK: Session plumbing

    private func prepare() {
        guard session == nil, !lesson.questions.isEmpty else { return }
        session = LearnSession(items: lesson.questions.map { .exercise($0.exercise) })
    }

    private func currentQuestionNumber(in session: LearnSession) -> Int? {
        guard let id = session.current?.exercise?.id else { return nil }
        return lesson.questions.first { $0.exercise.id == id }?.number
    }

    private func answeredNumbers(in session: LearnSession) -> Set<Int> {
        let done = Set(session.results.map(\.exerciseID))
        return Set(lesson.questions.filter { done.contains($0.exercise.id) }.map(\.number))
    }

    private func jump(to number: Int, in session: LearnSession) {
        guard let target = lesson.questions.first(where: { $0.number == number }),
              let index = session.items.firstIndex(where: { $0.exercise?.id == target.exercise.id })
        else { return }
        if index < session.index {
            // Jumping backwards rewinds the run; earlier results stay in the outcome.
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