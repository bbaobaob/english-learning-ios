import SwiftUI
import EnglishCore
import EnglishStore

/// The dictation drill, in two parts: a landing screen that chooses a set, and the
/// drill itself.
///
/// Grading is not here. `LearnSession.submitDictation(_:)` hands the text to
/// `DictationEngine`, and the returned `ExerciseResult` already carries
/// `isCorrect`, `accuracy`, `correctAnswer`, `explanation`, and the `[TokenDiff]`
/// this screen renders. There is no string comparison anywhere in this file, and
/// `firstErrorSummary` is reconstructed from the diffs for display rather than
/// recomputed.
struct DictationLandingView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                header

                if sets.isEmpty {
                    EmptyStateView(
                        symbol: "keyboard",
                        title: "No dictation yet",
                        message: "None of the loaded topics ship a dictation set. Lessons that have one will list it here.",
                        actionTitle: nil,
                        action: nil
                    )
                } else {
                    ForEach(sets, id: \.topicID) { set in
                        dictationSetCard(set)
                    }
                }

                Color.clear.frame(height: Spacing.xl)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
        }
        .background(PracticeBackdrop())
        .navigationTitle("Dictation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Listen, then write it exactly.")
                .font(AppFont.display(24, .bold))
                .accessibilityAddTraits(.isHeader)
            Text("Every set is plain speech, so it works offline. Replay as often as you need before you check.")
                .font(AppFont.display(14, .regular))
                .foregroundStyle(.secondary)
        }
    }

    private func dictationSetCard(_ set: DictationSet) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(set.title)
                    .font(AppFont.display(18, .bold))
                Spacer(minLength: Spacing.xs)
                if set.dueCount > 0 {
                    Text("Due")
                        .font(AppFont.mono(11, .bold))
                        .foregroundStyle(Color.warning)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Color.warning.opacity(0.16), in: Capsule())
                }
            }

            Text(set.subtitle)
                .font(AppFont.display(13, .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.md) {
                Chip(text: PracticeFormat.phrase(set.items.count, "sentence", "sentences"), isSelected: false)
                Chip(text: PracticeFormat.phrase(set.dueCount, "due", "due"), isSelected: set.dueCount > 0)
            }

            PrimaryButton(
                title: "Start drill",
                symbol: "play.fill",
                isEnabled: true,
                action: { chosen = set }
            )
            .navigationDestination(item: $chosen) { set in
                DictationView(title: set.title, items: set.items, topicID: set.topicID)
            }
        }
        .padding(Spacing.lg)
        .cardStyle()
    }

    @State private var chosen: DictationSet?

    /// Every dictation set the library offers, flattened per lesson.
    private var sets: [DictationSet] {
        guard let library = appState.library else { return [] }
        let dueByTopic = dueCountsByTopic
        var result: [DictationSet] = []
        for topic in library.allTopics {
            for lesson in topic.lessons {
                for step in lesson.steps {
                    guard case .dictation(let dictation) = step, !dictation.items.isEmpty else { continue }
                    result.append(
                        DictationSet(
                            topicID: topic.id,
                            title: dictation.title ?? lesson.title,
                            subtitle: "\(topic.title) · \(lesson.title)",
                            items: dictation.items,
                            dueCount: dueByTopic[topic.id] ?? 0
                        )
                    )
                }
            }
        }
        return result
    }

    /// Due review items per topic, for the "Due" badge.
    ///
    /// Read from the store's queue, bucketed by the topic each item names. No date
    /// arithmetic here — `reviewQueue(on:)` has already done the due filtering.
    private var dueCountsByTopic: [String: Int] {
        var counts: [String: Int] = [:]
        for item in appState.store.reviewQueue(on: Date()) {
            guard let topicID = item.topicID else { continue }
            counts[topicID, default: 0] += 1
        }
        return counts
    }
}

/// One selectable dictation set.
struct DictationSet: Identifiable, Hashable {
    var id: String { topicID + "::" + title }
    let topicID: String
    let title: String
    let subtitle: String
    let items: [DictationItem]
    let dueCount: Int
}

// MARK: - The drill

/// A dictation drill: a `LearnSession` over `[SessionItem.dictation]`, the shared
/// `ExerciseView` driving each item, and a score screen this file owns.
struct DictationView: View {

    let title: String
    let items: [DictationItem]
    let topicID: String

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var session: LearnSession?

    /// Slow replay rate, as a multiplier of the system's normal rate.
    ///
    /// The content's own rate wins when it is already slower. Expressed as a
    /// multiple rather than an absolute value because
    /// `AVSpeechUtterance.defaultSpeakingRate` is not a documented constant —
    /// a hardcoded `0.3` is too slow on a device whose normal rate is lower
    /// than expected, and the synthesizer ignores out-of-range rates silently
    /// rather than clamping them.
    private let slowRate: Float = SpeechRate.scaled(0.6)

    private var slot: String { "dictation:\(topicID):\(items.map(\.id).joined(separator: "-"))" }

    var body: some View {
        Group {
            if let session {
                if session.isFinished {
                    scoreScreen(session)
                } else {
                    drillScreen(session)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(PracticeBackdrop())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: resumeOrStart)
        .onDisappear {
            appState.speech.stop()
        }
    }

    // MARK: Live drill

    private func drillScreen(_ session: LearnSession) -> some View {
        VStack(spacing: 0) {
            headerStrip(session)

            // The whole per-item loop — play, replay, slow replay, type, check, reveal,
            // wrong-word highlight — belongs to App/Exercise. This screen only supplies
            // the session and the summary around it.
            // If the exercise lane takes the session plus a topic id, pass `topicID` too.
            ExerciseView(session: session)
                .id(session.index)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            transportBar(session)
        }
    }

    private func headerStrip(_ session: LearnSession) -> some View {
        HStack(spacing: Spacing.md) {
            Text("Item \(min(session.index + 1, session.items.count)) of \(session.items.count)")
                .font(AppFont.mono(12, .semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: Spacing.xs)

            if session.results.isEmpty {
                Text("Not graded yet")
                    .font(AppFont.display(12, .regular))
                    .foregroundStyle(.tertiary)
            } else {
                Text("Running \(PracticeFormat.percent(session.outcome.accuracy))")
                    .font(AppFont.mono(12, .bold))
                    .foregroundStyle(Color.accuracy)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    /// Floating transport: listen again, and listen again slowly.
    private func transportBar(_ session: LearnSession) -> some View {
        let item = currentItem(in: session)

        return HStack(spacing: Spacing.md) {
            SecondaryButton(
                title: "Listen again",
                symbol: "speaker.wave.2.fill",
                action: { speak(item, slow: false) }
            )
            SecondaryButton(
                title: "Slow",
                symbol: "tortoise.fill",
                action: { speak(item, slow: true) }
            )
        }
        .disabled(item == nil)
        .opacity(item == nil ? 0.5 : 1)
        .padding(Spacing.md)
        // Layout first, glass last, so the material wraps the final shape.
        .practiceFloatingGlass(cornerRadius: Radius.pill)
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.md)
        .accessibilityElement(children: .contain)
    }

    // MARK: Score

    private func scoreScreen(_ session: LearnSession) -> some View {
        let outcome = session.outcome

        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(outcome.accuracy >= 1 ? "Every word correct." : "Drill complete.")
                        .font(AppFont.display(28, .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(PracticeFormat.percent(outcome.accuracy) + " word accuracy across \(PracticeFormat.phrase(session.results.count, "sentence", "sentences")).")
                        .font(AppFont.display(15, .regular))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: Spacing.md) {
                    StatCard(
                        title: "XP",
                        value: outcome.xpEarned.formatted(.number),
                        caption: "earned in this drill",
                        symbol: "bolt.fill",
                        tint: .xp
                    )
                    StatCard(
                        title: "Wrong",
                        value: PracticeFormat.count(outcome.wrongIDs.count),
                        caption: "scheduled for today",
                        symbol: "exclamationmark.triangle.fill",
                        tint: .danger
                    )
                }

                VStack(alignment: .leading, spacing: Spacing.md) {
                    SectionHeader(
                        title: "Sentence by sentence",
                        subtitle: "Your own words, with the mismatch the engine found",
                        actionTitle: nil,
                        action: nil
                    )

                    ForEach(Array(session.results.enumerated()), id: \.offset) { pair in
                        resultCard(pair.element, index: pair.offset)
                    }
                }

                HStack(spacing: Spacing.md) {
                    PrimaryButton(
                        title: "Run it again",
                        symbol: "arrow.clockwise",
                        isEnabled: true,
                        action: {
                            Haptics.selection()
                            PracticeSessionStore.shared.reset(slot)
                            self.session = nil
                        }
                    )
                    SecondaryButton(
                        title: "Done",
                        symbol: "checkmark",
                        action: {
                            bankStudyTime(session)
                            dismiss()
                        }
                    )
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
    }

    private func resultCard(_ result: ExerciseResult, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: result.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.isCorrect ? Color.success : Color.danger)
                    .accessibilityHidden(true)
                Text("Sentence \(index + 1)")
                    .font(AppFont.display(16, .semibold))
                Spacer(minLength: Spacing.xs)
                Text(PracticeFormat.percent(result.accuracy))
                    .font(AppFont.mono(12, .bold))
                    .foregroundStyle(result.isCorrect ? Color.success : Color.danger)
            }

            if result.diffs.isEmpty {
                Text("Word for word.")
                    .font(AppFont.display(14, .regular))
                    .foregroundStyle(.secondary)
            } else {
                DiffChips(diffs: result.diffs)
            }

            if !result.explanation.isEmpty {
                Text(result.explanation)
                    .font(AppFont.display(14, .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let text = standardAnswer(result) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "text.quote")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(text)
                        .font(AppFont.mono(14, .regular))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.brandSoft.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            }

            // Listen again without leaving the result, so the learner can compare the
            // sentence against what they actually wrote.
            HStack(spacing: Spacing.md) {
                SecondaryButton(
                    title: "Listen again",
                    symbol: "speaker.wave.2.fill",
                    action: { speak(itemAt(index), slow: false) }
                )
                SecondaryButton(
                    title: "Slow",
                    symbol: "tortoise.fill",
                    action: { speak(itemAt(index), slow: true) }
                )
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .contain)
    }

    // MARK: Actions

    private func resumeOrStart() {
        guard session == nil else { return }
        session = PracticeSessionStore.shared.session(slot) {
            LearnSession(
                items: items.map { SessionItem.dictation($0) },
                onComplete: { _ in
                    Haptics.success()
                    PracticeSessionStore.shared.finish(slot)
                }
            )
        }
    }

    private func currentItem(in session: LearnSession) -> DictationItem? {
        guard case .dictation(let item) = session.current else { return nil }
        return item
    }

    /// The dictation item at a result's position. Results are appended in item order,
    /// so the two indices line up; the bound keeps a short list from trapping.
    private func itemAt(_ index: Int) -> DictationItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    private func speak(_ item: DictationItem?, slow: Bool) {
        guard let clip = item?.audio else { return }
        let rate = slow ? min(clip.speakingRate, slowRate) : clip.speakingRate
        appState.speech.speak(clip.text ?? clip.title ?? "", rate: rate) {}
        Haptics.selection()
    }

    /// The canonical sentence, straight from the graded `Answer` the engine returned.
    private func standardAnswer(_ result: ExerciseResult) -> String? {
        guard case .text(let values) = result.correctAnswer.values, let first = values.first else {
            return nil
        }
        return first
    }

    /// Records the drill as a study session so today's XP and streak include it.
    ///
    /// ponytail: minutes are a flat 1. A real timer would need a start instant and a
    //  survive-restart hook, and `registerStudy` wants whole minutes anyway — wire a
    //  `StartedAt` into `PracticeSessionStore` when per-minute study time matters.
    private func bankStudyTime(_ session: LearnSession) {
        appState.store.registerStudy(minutes: 1, xp: session.outcome.xpEarned, kind: .dictation)
    }
}

// MARK: - Diff presentation

/// Renders `[TokenDiff]` as the learner's own words with the mismatch called out.
///
/// So `"is play"` reads as *you wrote* `is play` — *should be* `is playing`. This is
/// presentation of the engine's output; nothing here compares strings.
struct DiffChips: View {

    let diffs: [TokenDiff]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(diffs) { diff in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Image(systemName: symbol(for: diff)).font(AppFont.body(.caption, weight: .bold))
                        .foregroundStyle(color(for: diff))
                        .frame(width: 16)
                        .accessibilityHidden(true)

                    Text(diff.user ?? "—")
                        .font(AppFont.mono(14, .regular))
                        .strikethrough(diff.user == nil, color: Color.danger)
                        .foregroundStyle(diff.user == nil ? Color.secondary : Color.primary)

                    Image(systemName: "arrow.right").font(AppFont.body(.caption2, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)

                    Text(diff.expected ?? "—")
                        .font(AppFont.mono(14, .bold))
                        .foregroundStyle(color(for: diff))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(color(for: diff).opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(phrase(for: diff))
            }
        }
    }

    private func symbol(for diff: TokenDiff) -> String {
        switch diff.kind {
        case .missing: "arrow.down.left"
        case .extra: "arrow.up.right"
        case .substituted: "arrow.left.arrow.right"
        }
    }

    private func color(for diff: TokenDiff) -> Color {
        switch diff.kind {
        case .missing: .warning
        case .extra: .danger
        case .substituted: .brand
        }
    }

    private func phrase(for diff: TokenDiff) -> String {
        switch diff.kind {
        case .missing: "Missing word: \(diff.expected ?? "")"
        case .extra: "Extra word: \(diff.user ?? "")"
        case .substituted: "You wrote \(diff.user ?? ""), it should be \(diff.expected ?? "")"
        }
    }
}
