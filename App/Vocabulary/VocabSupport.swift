import SwiftUI
import EnglishCore
import EnglishStore

// Shared vocabulary-lane scaffolding: the tab's navigation routes, read-only
// helpers over the two store APIs the lane is allowed to use, and the small
// presentational pieces (speak button, mastery bar, glass background) that every
// screen here repeats.
//
// Everything that decides *meaning* — scheduling, mastery, text comparison —
// belongs to EnglishCore. This file only reads and draws.

// MARK: - Navigation

/// Every destination reachable from inside the Vocabulary tab.
enum VocabRoute: Hashable {
    /// A word's detail screen, by word id.
    case detail(String)
    /// The spaced-repetition flashcard session over whatever is due today.
    case review
    /// The Hear → Type drill over an explicit list of word ids.
    case hearType([String])
    /// The Hear → Type drill over free practice words.
    case freeHearType
    /// A flashcard session narrowed to explicit word ids.
    case focusedReview([String])
}

// MARK: - Reading the learner's schedule

/// Read-only views over the persistence seams the lane is allowed to use.
///
/// The far-future date in ``all(from:)`` is deliberate and now the only place it
/// appears: this reads *every* vocabulary schedule at once, for grids and
/// sorting, and `reviewQueue(on:)` is the only bulk accessor the store has. A
/// single word uses `ProgressStore.reviewItem(forWordID:)` instead, which has no
/// sentinel in it.
@MainActor
enum VocabSchedule {

    /// Every persisted vocabulary schedule, keyed by word id, due or not.
    ///
    /// - Note: The `distantFuture` date is not a bug and not a shortcut for a
    ///   missing accessor. `reviewQueue(on:)` filters by due date, so a far-future
    ///   instant is the way to ask it for "all of them, scheduled or not" in one
    ///   fetch. `isDue` compares against this instant, so nothing is excluded for
    ///   being scheduled far out.
    static func all(from store: ProgressStore) -> [String: ReviewItem] {
        var result: [String: ReviewItem] = [:]
        for item in store.reviewQueue(on: Date.distantFuture) where item.source == .vocabulary {
            result[item.refID] = item
        }
        return result
    }

    /// The items a review session should offer right now, soonest first.
    static func dueToday(from store: ProgressStore) -> [ReviewItem] {
        store.reviewQueue(on: Date()).filter { $0.source == .vocabulary }
    }

    /// The persisted schedule for one word, or a brand-new item when the word
    /// has never been reviewed.
    ///
    /// - Parameters:
    ///   - wordID: The word to look up.
    ///   - schedule: A pre-read schedule map, so a list of words costs one fetch.
    static func item(for wordID: String, in schedule: [String: ReviewItem]) -> ReviewItem {
        schedule[wordID] ?? SpacedRepetition.makeItem(
            source: .vocabulary,
            refID: wordID,
            topicID: nil,
            now: Date()
        )
    }

    /// The learner's most-missed words, hardest first.
    ///
    /// Lapsed words come first because a lapse is the only evidence of having
    /// been learned and then lost; recently-wrong words fill the remainder so
    /// the section is never empty for a learner mid-session.
    static func weakWords(from store: ProgressStore, limit: Int) -> [ReviewItem] {
        let items = all(from: store)
        let queue = ReviewQueue(Array(items.values))
        let lapsed = queue.difficult.sorted { $0.lapses > $1.lapses }
        let seen = Set(lapsed.map(\.refID))
        let filler = queue.recentlyWrong(limit: limit).filter { !seen.contains($0.refID) }
        return Array((lapsed + filler).prefix(limit))
    }
}

// MARK: - Session pacing

/// How long the tab estimates a session will take.
///
/// A display estimate, not scheduling: it multiplies the word count by a fixed
/// per-card cost and never touches a due date.
enum VocabPace {
    /// Seconds of card flipping, rating and speaking per word.
    static let secondsPerWord = 12

    /// A short phrase such as `"4 min"`, `"1 min"` or `"under a minute"`.
    static func estimate(wordCount: Int) -> String {
        let minutes = Int((Double(max(0, wordCount)) * Double(secondsPerWord) / 60).rounded(.up))
        return minutes < 1 ? "under a minute" : "\(minutes) min"
    }

    /// The longest free-practice session the tab will assemble.
    static let freePracticeLimit = 10
}

// MARK: - Colour and material helpers

extension Color {
    /// The tint for a stored mastery value in `0...1`.
    ///
    /// Purely presentational: it bands the value the store already stored so a
    /// glanceable row does not need a number.
    static func masteryTint(_ mastery: Double) -> Color {
        switch mastery {
        case 0.85...: .success
        case 0.45..<0.85: .brand
        case 0.01..<0.45: .warning
        default: .secondary
        }
    }
}

extension View {
    /// Liquid Glass on floating controls, with a material fallback before iOS 26.
    ///
    /// Applied *after* layout modifiers by the call sites that use it, because
    /// the glass shape must be resolved from the laid-out size.
    @ViewBuilder
    func vocabGlass(cornerRadius: CGFloat = Radius.card) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }

    /// The soft aurora wash behind the tab header.
    @ViewBuilder
    func vocabAurora() -> some View {
        self.background(
            RadialGradient(
                colors: [Color.brand.opacity(0.30), Color.brandSoft.opacity(0.14), .clear],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 340
            )
            .ignoresSafeArea(edges: .top)
        )
    }
}

// MARK: - Presentational pieces

/// A round, always-tappable speaker button.
///
/// Every listening affordance in this lane is a real `Button`, so nothing here
/// depends on a gesture and nothing is hidden behind VoiceOver's "activate".
struct VocabSpeakButton: View {
    @Environment(AppState.self) private var appState

    /// The text to speak.
    let text: String
    /// `AVSpeechUtterance` rate. Defaults to the system's normal rate; every
    /// drill passes a ``SpeechRate`` name so the value is never a bare literal.
    var rate: Float = SpeechRate.normalSpeed
    /// Spoken by VoiceOver in place of the symbol name.
    var accessibilityLabel: String
    /// Diameter of the button.
    var size: CGFloat = 38

    var body: some View {
        Button {
            Haptics.selection()
            appState.speech.speak(text, rate: rate, completion: nil)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Color.brand)
                .frame(width: size, height: size)
                .background(Color.brandSoft.opacity(0.55), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// The six-letter slot of the word itself, for the flashcard front.
///
/// `Text` with monospaced digits and `minimumScaleFactor` keeps the IPA from
/// clipping at the largest Dynamic Type sizes: the scale factor, not a fixed
/// frame, absorbs the growth.
struct VocabWordText: View {
    let text: String
    /// Extra tracking, in points.
    var tracking: CGFloat = 0

    var body: some View {
        Text(text)
            .font(AppFont.display(.largeTitle, weight: .bold))
            .tracking(tracking)
            .minimumScaleFactor(0.55)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

/// The phonetic transcription, set in the mono face so `/ˈwɔːtə/` lines up
/// character by character. Scaled rather than truncated at large type sizes.
struct VocabIPAText: View {
    let ipa: String
    var size: CGFloat = 16

    var body: some View {
        Text(ipa)
            .font(AppFont.mono(size, weight: .regular))
            .foregroundStyle(.secondary)
            .minimumScaleFactor(0.6)
            .lineLimit(2)
            .textSelection(.enabled)
            .accessibilityLabel("Pronounced \(ipa)")
    }
}

/// A thin mastery meter for list rows.
///
/// Draws the value the store stored; it does not derive one.
struct VocabMasteryBar: View {
    let mastery: Double

    private var clamped: Double { min(1, max(0, mastery)) }

    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.secondary.opacity(0.18))
            .frame(width: 52, height: 5)
            .overlay(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.masteryTint(clamped))
                    .frame(width: 52 * clamped, height: 5)
            }
            .accessibilityElement()
            .accessibilityLabel("Mastery")
            .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }
}

/// A small label used for topic and level metadata.
struct VocabTagText: View {
    let text: String

    var body: some View {
        Text(text).font(AppFont.body(.footnote, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: .capsule)
    }
}

/// A tappable related-word chip, showing the current word as selected.
struct VocabRelatedChip: View {
    let text: String
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Chip(text: text, isSelected: isCurrent, action: action)
    }
}
