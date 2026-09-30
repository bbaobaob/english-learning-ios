import SwiftUI
import EnglishCore

/// One thing to hear and type.
///
/// Built from the letter lesson's own content: the letter name is spoken from the
/// lesson's own audio clip, and the word comes from the lesson's first example.
/// Nothing is hardcoded here, so the mode follows the content.
struct ListeningItem: Identifiable, Hashable {

    enum Kind: String, Hashable {
        case letter
        case word

        var title: String {
            switch self {
            case .letter: "Letter name"
            case .word: "Word"
            }
        }

        var prompt: String {
            switch self {
            case .letter: "Type the letter you hear."
            case .word: "Type the word you hear."
            }
        }

        var symbol: String {
            switch self {
            case .letter: "character"
            case .word: "text.word"
            }
        }
    }

    let id: String
    let lessonID: String
    let letter: String
    let kind: Kind
    /// What the synthesiser reads aloud.
    let speechText: String
    /// Every form the answer is allowed to take; all go through the normalizer.
    let accepted: [String]
    let hint: String?
    /// Shown on a correct answer, next to the letter.
    let reveal: String?
}

/// Builds the Listening Mode item list from the alphabet topic's lessons.
///
/// - Parameters:
///   - library: the loaded content.
///   - lettersOnly: when true only the 26 letter items, otherwise the word items
///     too. The full set is 52 items, which is a long sitting.
func listeningItems(
    from library: ContentLibrary,
    lettersOnly: Bool
) -> [ListeningItem] {
    guard let topic = library.topic("alphabet") else { return [] }
    var items: [ListeningItem] = []

    for lesson in topic.lessons {
        let letter = AlphabetCard.letter(in: lesson)

        // The letter name: the lesson's own audio clip when it ships one,
        // otherwise the plain letter, which the synthesiser reads as a name.
        let clipText = lesson.steps.compactMap { step -> String? in
            if case .audio(let step) = step { return step.audio.text }
            return nil
        }.first
        items.append(
            ListeningItem(
                id: "\(lesson.id)-letter",
                lessonID: lesson.id,
                letter: letter,
                kind: .letter,
                speechText: clipText ?? letter.uppercased(),
                accepted: [letter.uppercased(), letter.lowercased()],
                hint: nil,
                reveal: nil
            )
        )

        guard !lettersOnly, let word = AlphabetCard.exampleWord(in: lesson) else { continue }
        let hint = lesson.steps.compactMap { step -> String? in
            if case .examples(let step) = step { return step.examples.first?.note }
            return nil
        }.first
        items.append(
            ListeningItem(
                id: "\(lesson.id)-word",
                lessonID: lesson.id,
                letter: letter,
                kind: .word,
                speechText: word,
                accepted: [word],
                hint: hint,
                reveal: word
            )
        )
    }

    return items
}

// MARK: - Session state

/// How one item currently stands.
fileprivate enum ListenPhase {
    /// Played (or not yet played); the learner has not submitted anything.
    case fresh
    /// Submitted and wrong: the answer is shown and they may try again.
    case wrong
    /// Submitted and right: revealed, and ready to move on.
    case correct
}

/// The listening session. Owns only presentation state; every judgement of an
/// answer is delegated to `AnswerNormalizer`, and nothing here is persisted.
@MainActor
@Observable
final class ListeningSession {

    let items: [ListeningItem]
    let normalizer = AnswerNormalizer()

    private(set) var index: Int = 0
    fileprivate private(set) var phase: ListenPhase = .fresh
    /// Whether the current item's audio has been played at least once.
    private(set) var hasPlayedCurrent: Bool = false
    /// Attempts per item id. Slow audio never counts as an attempt.
    private(set) var attempts: [String: Int] = [:]
    /// Replays per item id, shown in the recap and never scored.
    private(set) var replays: [String: Int] = [:]
    /// Items answered correctly, whether first try or later.
    private(set) var resolved: Set<String> = []
    /// Items answered correctly on the very first submission.
    private(set) var firstTry: Set<String> = []

    init(items: [ListeningItem]) {
        self.items = items
    }

    var current: ListeningItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    /// True before the first item and after the last one.
    var isFinished: Bool { !items.indices.contains(index) }
    var isEmpty: Bool { items.isEmpty }

    var isCorrectNow: Bool { phase == .correct }
    var isWrongNow: Bool { phase == .wrong }
    var isFreshNow: Bool { phase == .fresh }

    /// Submissions on the current item. The next go is one higher.
    var currentAttemptCount: Int {
        current.map { attempts[$0.id, default: 0] } ?? 0
    }

    /// Items answered right at least once.
    var passedCount: Int { resolved.count }
    /// Items answered right on the first submission.
    var firstTryCount: Int { firstTry.count }
    var totalReplays: Int {
        items.reduce(0) { $0 + replays[$1.id, default: 0] }
    }

    /// Records that the current item's audio was played.
    func markPlayed() {
        hasPlayedCurrent = true
        guard let current else { return }
        replays[current.id, default: 0] += 1
    }

    /// Grades `text` against the current item's accepted answers.
    ///
    /// An empty field is not a wrong answer: it leaves the item fresh so the
    /// learner is not shown a red box for tapping Check on nothing.
    @discardableResult
    func submit(_ text: String) -> Bool {
        guard let current else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        attempts[current.id, default: 0] += 1
        guard !trimmed.isEmpty else {
            phase = .fresh
            return false
        }

        let isCorrect = current.accepted.contains { normalizer.isEquivalent(trimmed, $0) }
        phase = isCorrect ? .correct : .wrong
        if isCorrect {
            resolved.insert(current.id)
            if attempts[current.id] == 1 { firstTry.insert(current.id) }
        }
        return isCorrect
    }

    /// Rolls the current item back to unanswered, ready for another go.
    func retry() {
        phase = .fresh
        hasPlayedCurrent = false
    }

    /// Moves to the next item. Returns false once the session is done.
    @discardableResult
    func next() -> Bool {
        guard items.indices.contains(index) else { return false }
        index += 1
        phase = .fresh
        hasPlayedCurrent = false
        return items.indices.contains(index)
    }
}

// MARK: - View

/// Listening Mode: hear it, type it, check it.
///
/// Deliberately not the exercise list with new wording. One prompt fills the
/// screen, the keyboard is up, and the only decisions are replay, slow, and
/// check. Using the slow button is the intended way to play, so it never costs
/// the learner anything.
struct AlphabetListeningView: View {

    @Environment(AppState.self) private var app

    @State private var lettersOnly = false
    @State private var session: ListeningSession?
    @State private var input: String = ""
    @FocusState private var inputFocused: Bool

    private var items: [ListeningItem] {
        guard let library = app.library else { return [] }
        return listeningItems(from: library, lettersOnly: lettersOnly)
    }

    var body: some View {
        Group {
            if let session {
                content(session: session)
            } else if items.isEmpty {
                EmptyStateView(
                    symbol: "ear.slash",
                    title: "Nothing to listen to",
                    message: "The alphabet course is not in the content bundle that shipped with the app.",
                    actionTitle: nil,
                    action: nil
                )
            } else {
                intro
            }
        }
        .navigationTitle("Listening Mode")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { inputFocused = false }
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(spacing: Spacing.lg) {
            Spacer(minLength: Spacing.lg)

            Image(systemName: "ear.badge.waveform")
                .font(.system(size: 56))
                .foregroundStyle(.brand)
                .accessibilityHidden(true)

            Text("Type what you hear").font(AppFont.display(.largeTitle))
                .multilineTextAlignment(.center)

            Text("Each letter is read out. Type it, then check. Replay and slow audio as many times as you need — using them costs you nothing.").font(AppFont.body(.body))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Spacing.lg)

            Toggle(isOn: $lettersOnly) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Letters only").font(AppFont.body(.subheadline, weight: .semibold))
                    Text(lettersOnly
                        ? "26 items, one per letter name."
                        : "52 items: the letter name, then a word it appears in.").font(AppFont.body(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Spacing.md)
            .background(Color.brand.opacity(0.08), in: .rect(cornerRadius: Radius.card))

            PrimaryButton(
                title: "Start",
                symbol: "play.fill",
                isEnabled: true,
                action: {
                    Haptics.selection()
                    session = ListeningSession(items: items)
                    input = ""
                }
            )
            .padding(.horizontal, Spacing.lg)

            Spacer(minLength: Spacing.lg)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Flow

    @ViewBuilder
    private func content(session: ListeningSession) -> some View {
        if session.isEmpty {
            EmptyStateView(
                symbol: "tray",
                title: "Nothing to listen to",
                message: "There are no items in this session.",
                actionTitle: nil,
                action: nil
            )
        } else if session.isFinished {
            recap(session: session)
        } else if let item = session.current {
            prompt(item: item, session: session)
        }
    }

    private func prompt(item: ListeningItem, session: ListeningSession) -> some View {
        VStack(spacing: Spacing.lg) {
            header(item: item, session: session)

            Spacer(minLength: 0)

            playControls(item: item, session: session)

            inputArea(item: item, session: session)

            answerArea(item: item, session: session)

            Spacer(minLength: 0)

            actionArea(item: item, session: session)
        }
        .id(item.id)
        .onAppear {
            // The keyboard is the whole interaction here, so it comes up with
            // the prompt rather than making the learner tap the field first.
            inputFocused = true
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.md)
    }

    // MARK: - Pieces

    private func header(item: ListeningItem, session: ListeningSession) -> some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(item.kind.prompt).font(AppFont.body(.headline))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.sm) {
                    Label(item.kind.title, systemImage: item.kind.symbol).font(AppFont.body(.caption))
                        .foregroundStyle(.secondary)
                    if session.currentAttemptCount > 0 {
                        Text("try \(session.currentAttemptCount + 1)").font(AppFont.mono(.caption))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            Text("\(session.index + 1) / \(session.items.count)").font(AppFont.mono(.caption))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Item \(session.index + 1) of \(session.items.count)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.sm)
    }

    /// The audio controls. Slow is a first-class button, not a hidden option.
    private func playControls(item: ListeningItem, session: ListeningSession) -> some View {
        HStack(spacing: Spacing.lg) {
            Button {
                session.markPlayed()
                SpeakGate.say(item.speechText, using: app)
                Haptics.selection()
            } label: {
                Image(systemName: session.hasPlayedCurrent ? "speaker.wave.2.circle.fill" : "speaker.wave.2.circle")
                    .font(.system(size: 64))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.brand)
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .background(Color.brand.opacity(0.08), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.hasPlayedCurrent ? "Replay" : "Play the audio")
            .accessibilityHint("Reads it out loud again at normal speed")

            Button {
                session.markPlayed()
                SpeakGate.say(item.speechText, using: app, absoluteRate: SpeakGate.slowRate)
                Haptics.selection()
            } label: {
                VStack(spacing: Spacing.xs) {
                    Image(systemName: "tortoise.fill").font(AppFont.body(.title))
                    Text("Slow").font(AppFont.body(.caption, weight: .semibold))
                }
                .foregroundStyle(.brand)
                .frame(minWidth: 72, minHeight: 76)
                .background(Color.brand.opacity(0.08), in: .rect(cornerRadius: Radius.card))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play slowly")
            .accessibilityHint("Reads it at a slower pace. This does not count against you.")
        }
    }

    private func inputArea(item: ListeningItem, session: ListeningSession) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            TextField(item.kind == .letter ? "One letter" : "One word", text: $input)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled().font(AppFont.body(.title3, weight: .semibold))
                .padding(Spacing.md)
                .background(inputBackground(session: session))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.chip)
                        .strokeBorder(border(session: session), lineWidth: 2)
                }
                .focused($inputFocused)
                .submitLabel(.done)
                .onSubmit { check(item: item, session: session) }
                .accessibilityLabel(item.kind == .letter ? "Your answer, one letter" : "Your answer, one word")

            if session.isWrongNow {
                Label("Not quite — the answer is below", systemImage: "xmark.circle.fill").font(AppFont.body(.caption, weight: .semibold))
                    .foregroundStyle(.danger)
            }
        }
    }

    private func inputBackground(session: ListeningSession) -> some View {
        RoundedRectangle(cornerRadius: Radius.chip)
            .fill(session.isWrongNow ? Color.danger.opacity(0.12) : Color(.secondarySystemBackground))
    }

    private func border(session: ListeningSession) -> Color {
        if session.isCorrectNow { return .success }
        if session.isWrongNow { return .danger }
        return .clear
    }

    /// The reveal. Shows the right answer after a wrong go, and the letter with
    /// its word after a right one.
    @ViewBuilder
    private func answerArea(item: ListeningItem, session: ListeningSession) -> some View {
        if session.isCorrectNow {
            HStack(spacing: Spacing.md) {
                Text(item.letter.uppercased())
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.brand)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(item.accepted.first ?? item.speechText).font(AppFont.body(.title3, weight: .semibold))
                    if let reveal = item.reveal {
                        Text(reveal).font(AppFont.body(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(Color.success.opacity(0.14), in: .rect(cornerRadius: Radius.card))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Correct. \(item.letter.uppercased()). \(item.reveal ?? "")")

        } else if session.isWrongNow {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("The answer was").font(AppFont.body(.caption))
                    .foregroundStyle(.secondary)
                Text(item.accepted.first ?? item.speechText).font(AppFont.body(.title3, weight: .semibold))
                if let hint = item.hint {
                    Text(hint).font(AppFont.body(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(Color.danger.opacity(0.10), in: .rect(cornerRadius: Radius.card))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("The answer is \(item.accepted.first ?? item.speechText)")

        } else if session.isFreshNow, !session.hasPlayedCurrent {
            Text("Nothing played yet. Tap the speaker to hear it.").font(AppFont.body(.footnote))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func actionArea(item: ListeningItem, session: ListeningSession) -> some View {
        switch session.phase {
        case .fresh:
            PrimaryButton(
                title: "Check",
                symbol: "checkmark",
                isEnabled: !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: {
                    check(item: item, session: session)
                }
            )
        case .wrong:
            VStack(spacing: Spacing.sm) {
                PrimaryButton(
                    title: "Try again",
                    symbol: "arrow.counterclockwise",
                    isEnabled: true,
                    action: {
                        session.retry()
                        input = ""
                        inputFocused = true
                        Haptics.selection()
                    }
                )
                Text("Listen as often as you like before trying again.").font(AppFont.body(.caption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        case .correct:
            PrimaryButton(
                title: session.index + 1 < session.items.count ? "Next" : "Finish",
                symbol: session.index + 1 < session.items.count ? "arrow.right" : "flag.checkered",
                isEnabled: true,
                action: {
                    Haptics.success()
                    input = ""
                    session.next()
                }
            )
        }
    }

    // MARK: - Recap

    private func recap(session: ListeningSession) -> some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                ProgressRing(
                    progress: Double(session.passedCount) / Double(max(session.items.count, 1)),
                    lineWidth: 12,
                    tint: session.passedCount == session.items.count ? .success : .brand,
                    label: "\(session.passedCount) of \(session.items.count)"
                )
                .padding(.top, Spacing.md)

                Text(session.passedCount == session.items.count ? "Every one" : "Session done").font(AppFont.display(.title2))

                Text("\(session.passedCount) of \(session.items.count) correct, \(session.firstTryCount) of them first try.").font(AppFont.body(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                StatCard(
                    title: "First try",
                    value: "\(session.firstTryCount)/\(session.items.count)",
                    caption: "no replays needed",
                    symbol: "bolt.fill",
                    tint: .brand
                )
                StatCard(
                    title: "Needing more than one go",
                    value: "\(session.items.count - session.firstTryCount)",
                    caption: "these are the ones to revisit",
                    symbol: "arrow.triangle.2.circlepath",
                    tint: .warning
                )

                // Slow audio is never counted against the learner; it is only
                // shown so the recap can reassure rather than score it.
                if session.totalReplays > 0 {
                    Label(
                        "\(session.totalReplays) replays used — free, and they cost you nothing.",
                        systemImage: "tortoise"
                    ).font(AppFont.body(.footnote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
                }

                VStack(spacing: Spacing.sm) {
                    SecondaryButton(
                        title: "Run it again",
                        symbol: "arrow.counterclockwise",
                        action: {
                            session = ListeningSession(items: items)
                            input = ""
                        }
                    )
                    Button {
                        session = nil
                        input = ""
                    } label: {
                        Text("Change the item set").font(AppFont.body(.subheadline, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.brand)
                }
                .padding(.bottom, Spacing.lg)
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    // MARK: - Submit

    private func check(item: ListeningItem, session: ListeningSession) {
        inputFocused = false
        let isCorrect = session.submit(input)
        if isCorrect {
            Haptics.success()
        } else {
            Haptics.failure()
        }
    }
}
