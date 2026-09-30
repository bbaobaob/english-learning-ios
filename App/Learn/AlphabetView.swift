import SwiftUI
import EnglishCore

/// The 26-letter course as a grid of tappable cards.
///
/// Each card carries the letter in both cases, the example word pulled from the
/// lesson's own content, and a tick when the learner has completed that lesson.
/// Above the grid sits the Listening Mode entry, which is a different way of
/// working the same material, not a different grid.
struct AlphabetView: View {

    @Environment(AppState.self) private var app

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: Spacing.md)]

    private var topic: Topic? { app.library.topic("alphabet") }

    private var lessons: [Lesson] { topic?.lessons ?? [] }

    /// Fraction of the 26 letters finished.
    private var completion: Double {
        let progress = app.store.lessonProgress()
        let done = lessons.filter { progress[$0.id]?.completed == true }.count
        guard !lessons.isEmpty else { return 0 }
        return Double(done) / Double(lessons.count)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                header
                listeningEntry

                if lessons.isEmpty {
                    EmptyStateView(
                        symbol: "textformat",
                        title: "Alphabet not loaded",
                        message: "The alphabet course is not in the content bundle that shipped with the app.",
                        actionTitle: nil,
                        action: nil
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: Spacing.md) {
                        ForEach(lessons) { lesson in
                            letterCard(for: lesson)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.brand.opacity(0.04).ignoresSafeArea())
        .navigationTitle("Alphabet")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: LearnRoute.self) { route in
            switch route {
            case .lesson(let topicID, let lessonID):
                LessonView(topicID: topicID, lessonID: lessonID)
            case .alphabetListening:
                AlphabetListeningView()
            case .alphabet:
                EmptyStateView(
                    symbol: "textformat",
                    title: "Already here",
                    message: "You are looking at the alphabet course.",
                    actionTitle: "Back",
                    action: { app.navigationPath.removeLast() }
                )
            case .topic(let id):
                if let next = app.library.topic(id) {
                    TopicDetailView(topic: next)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.lg) {
                ProgressRing(
                    progress: completion,
                    lineWidth: 10,
                    tint: .brand,
                    label: "\(Int((completion * 100).rounded())) percent"
                )
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(topic?.title ?? "The English Alphabet")
                        .font(.title2.bold())
                    Text(topic?.summary ?? "One lesson per letter: the shapes, the sound, and the word it lives in.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Alphabet progress, \(Int((completion * 100).rounded())) percent complete")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .padding(.top, Spacing.sm)
    }

    private var listeningEntry: some View {
        NavigationLink(value: LearnRoute.alphabetListening) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "ear.badge.waveform")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.brand, in: .rect(cornerRadius: Radius.chip))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Listening Mode")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Hear it, type it, check it. Replay as often as you like.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Listening Mode. Hear it, type it, check it.")
        .accessibilityHint("Starts a typing-from-hearing session across all 26 letters")
    }

    // MARK: - Card

    private func letterCard(for lesson: Lesson) -> some View {
        let isComplete = app.store.lessonProgress()[lesson.id]?.completed == true
        let letter = AlphabetCard.letter(in: lesson)
        let word = AlphabetCard.exampleWord(in: lesson)

        return NavigationLink(value: LearnRoute.lesson(topicID: "alphabet", lessonID: lesson.id)) {
            VStack(spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(letter.uppercased())
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.brand)
                    Text(letter.lowercased())
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.brand.opacity(0.75))
                    Spacer(minLength: 0)
                    if isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.success)
                            .accessibilityHidden(true)
                    }
                }

                Text(word ?? "Letter \(letter.uppercased())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if !isComplete {
                    Text(lesson.summary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Letter \(letter.uppercased()). \(lesson.summary)")
        .accessibilityValue(isComplete ? "Completed" : "Not started")
        .accessibilityHint("Double tap to open the lesson")
    }
}

/// Pulls the letter and its example word out of the lesson's own content, so the
/// grid never hardcodes anything the content does not already say.
enum AlphabetCard {

    /// The letter a lesson teaches, from a title like "The letter A".
    static func letter(in lesson: Lesson) -> String {
        let trimmed = lesson.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = trimmed.split(separator: " ").last, last.count == 1 {
            return String(last)
        }
        if let range = trimmed.range(of: "letter ", options: .caseInsensitive) {
            return String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return String(trimmed.prefix(1))
    }

    /// The first single-word example in the lesson, which is the letter's word.
    static func exampleWord(in lesson: Lesson) -> String? {
        var candidates: [Example] = []
        for step in lesson.steps {
            switch step {
            case .examples(let step):
                candidates.append(contentsOf: step.examples)
            case .theory(let step):
                candidates.append(contentsOf: step.rules.flatMap(\.examples))
            default:
                break
            }
        }
        return candidates
            .map { $0.en.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.count > 1 && !$0.contains(" ") }
    }
}
