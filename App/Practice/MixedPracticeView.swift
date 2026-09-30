import SwiftUI
import EnglishCore
import EnglishStore

/// A mixed set: every exercise from one skill at one level, shuffled by lesson order.
///
/// It owns no interaction at all. `LearnSession` resolves the items, `ExerciseView`
/// drives them, and the store records the attempts. This view is the summary shell
/// and the place the XP gets banked.
struct MixedPracticeView: View {

    let topicID: String
    let skill: CoreSkill
    let level: Level

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var session: LearnSession?
    @State private var banked = false

    private var slot: String { "practice:\(topicID):\(level.rawValue)" }

    var body: some View {
        Group {
            if let session {
                if session.isFinished {
                    scoreScreen(session)
                } else {
                    runningScreen(session)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(PracticeBackdrop())
        .navigationTitle("Practice · \(level.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: resumeOrStart)
    }

    // MARK: - Running

    private func runningScreen(_ session: LearnSession) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.md) {
                Text("\(min(session.index + 1, session.items.count)) of \(session.items.count)")
                    .font(AppFont.mono(12, .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: Spacing.xs)
                if session.results.isEmpty {
                    Text("Not graded yet")
                        .font(AppFont.display(12, .regular))
                        .foregroundStyle(.tertiary)
                } else {
                    Text(PracticeFormat.percent(session.outcome.accuracy))
                        .font(AppFont.mono(12, .bold))
                        .foregroundStyle(Color.accuracy)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .accessibilityElement(children: .combine)

            ExerciseView(session: session)
                .id(session.index)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Score

    private func scoreScreen(_ session: LearnSession) -> some View {
        let outcome = session.outcome

        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(outcome.wrongIDs.isEmpty ? "Clean sweep." : "Set complete.")
                        .font(AppFont.display(28, .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(PracticeFormat.percent(outcome.accuracy) + " across "
                         + PracticeFormat.phrase(session.results.count, "exercise", "exercises") + ".")
                        .font(AppFont.display(15, .regular))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: Spacing.md) {
                    StatCard(
                        title: "XP",
                        value: outcome.xpEarned.formatted(.number),
                        caption: "this set",
                        symbol: "bolt.fill",
                        tint: .xp
                    )
                    StatCard(
                        title: "To review",
                        value: PracticeFormat.count(outcome.wrongIDs.count),
                        caption: "scheduled for today",
                        symbol: "arrow.uturn.backward",
                        tint: .danger
                    )
                }

                if !outcome.wrongIDs.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        SectionHeader(
                            title: "Coming back",
                            subtitle: "Each of these is in today's review queue",
                            actionTitle: nil,
                            action: nil
                        )
                        ForEach(outcome.wrongIDs, id: \.self) { id in
                            HStack(alignment: .top, spacing: Spacing.sm) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(Color.danger)
                                    .accessibilityHidden(true)
                                Text(appState.library?.exercise(id)?.prompt ?? id)
                                    .font(AppFont.display(14, .regular))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardStyle()
                        }
                    }
                }

                HStack(spacing: Spacing.md) {
                    PrimaryButton(
                        title: "Again",
                        symbol: "arrow.clockwise",
                        isEnabled: true,
                        action: {
                            Haptics.selection()
                            PracticeSessionStore.shared.reset(slot)
                            session = nil
                        }
                    )
                    SecondaryButton(
                        title: "Done",
                        symbol: "checkmark",
                        action: finish
                    )
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .onAppear { bankStudyTime(session) }
    }

    // MARK: - Actions

    private func resumeOrStart() {
        guard session == nil else { return }
        guard let topic = appState.library?.topic(topicID) else { return }
        let items = topic.exercises(at: level)

        session = PracticeSessionStore.shared.session(slot) {
            LearnSession(
                items: items.map { SessionItem.exercise($0) },
                onComplete: { _ in
                    Haptics.success()
                    PracticeSessionStore.shared.finish(slot)
                }
            )
        }
    }

    private func finish() {
        dismiss()
    }

    /// Records the set once, the first time the score screen appears.
    ///
    /// ponytail: the guard is a plain flag rather than a persisted marker, so a set
    /// interrupted by backgrounding cannot double-count the XP. The store's
    /// `registerStudy` is the only thing called; the XP number is the engine's.
    private func bankStudyTime(_ session: LearnSession) {
        guard !banked else { return }
        banked = true
        appState.store.registerStudy(minutes: 1, xp: session.outcome.xpEarned, kind: skill.studyKind)
    }
}
