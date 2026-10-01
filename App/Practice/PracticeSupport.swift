import SwiftUI
import EnglishCore
import EnglishStore

// MARK: - The four core skills

/// The four skills the Practice tab is built around, in study order.
///
/// This is the tab's spine: it is the only place that decides which `TopicKind`
/// counts as a "core skill" and what each one is called in the UI. Everything else
/// reads the descriptor.
enum CoreSkill: String, CaseIterable, Identifiable, Hashable {
    case listening
    case speaking
    case reading
    case writing

    var id: String { rawValue }

    /// The `TopicKind` this skill is sourced from.
    var kind: TopicKind {
        switch self {
        case .listening: .listening
        case .speaking: .speaking
        case .reading: .reading
        case .writing: .writing
        }
    }

    /// Tab-facing name.
    var title: String {
        switch self {
        case .listening: "Listening"
        case .speaking: "Speaking"
        case .reading: "Reading"
        case .writing: "Writing"
        }
    }

    /// The one-line promise shown under the skill's name: what this trains.
    var promise: String {
        switch self {
        case .listening: "Catch the sentence, not just the words."
        case .speaking: "Say it out loud until it sounds like speech."
        case .reading: "Read for meaning, then for the detail underneath."
        case .writing: "Get the sentence right before you style it."
        }
    }

    /// SF Symbol used on the skill card when the topic declares no icon of its own.
    var fallbackSymbol: String {
        switch self {
        case .listening: "ear"
        case .speaking: "waveform"
        case .reading: "text.book.closed"
        case .writing: "square.and.pencil"
        }
    }

    /// The symbol used on the utility rows and headers.
    var symbol: String { fallbackSymbol }

    /// The `StudyKind` a session of this skill records.
    var studyKind: StudyKind {
        switch self {
        case .listening: .listening
        case .speaking: .speaking
        case .reading: .reading
        case .writing: .writing
        }
    }
}

// MARK: - Level

extension Level {
    /// Capitalised name for `LevelPill` and segmented controls.
    var displayName: String {
        switch self {
        case .beginner: "Beginner"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        }
    }

    /// The three levels in study order.
    static let studyOrder: [Level] = [.beginner, .intermediate, .advanced]
}

// MARK: - Topic and lesson slicing

extension Topic {
    /// This topic's `CoreSkill`, or `nil` for grammar, vocabulary, IELTS, and the rest.
    var coreSkill: CoreSkill? {
        CoreSkill(rawValue: kind.rawValue)
    }

    /// This topic's lessons at `level`, in study order.
    func lessons(at level: Level) -> [Lesson] {
        lessons.filter { $0.resolvedLevel(fallback: self.level) == level }
    }

    /// Every exercise in the topic's lessons at `level`, in lesson then step order.
    func exercises(at level: Level) -> [Exercise] {
        lessons(at: level).flatMap(\.exercises)
    }

    /// Every dictation item in the topic, across all levels, in study order.
    var dictationItems: [DictationItem] {
        lessons.flatMap { lesson in
            lesson.steps.compactMap { step in
                if case .dictation(let dictation) = step { return dictation.items }
                return nil
            }
        }
    }

    /// Share of this topic's lessons that are finished, `0...1`, for a ring.
    ///
    /// Counting lesson completion rather than exercise counts is deliberate: the
    /// content library knows how many lessons a topic has, and nothing in the store
    /// knows the exercise total per level.
    func lessonCompletion(_ rows: [String: LessonProgress]) -> Double {
        guard !lessons.isEmpty else { return 0 }
        let done = lessons.filter { rows[$0.id]?.completed == true }.count
        return Double(done) / Double(lessons.count)
    }
}

// MARK: - Formatting

/// Number and percentage formatters shared by the Practice screens.
///
/// A view formats; it never recomputes. Everything here reads a value the engine or
/// the store already produced.
enum PracticeFormat {

    /// `0.83` becomes `83%`.
    static func percent(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    /// A whole number with a thin separator, e.g. `1,240`.
    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    /// A minute figure that reads naturally at 0, 1, and 90.
    static func minutes(_ value: Int) -> String {
        value.formatted(.number) + " min"
    }

    /// An ease factor to two decimals, e.g. `2.50`.
    static func ease(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    /// Seconds as `m:ss`, for the speaking timer.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// The learner's own words, in the shape a result card wants them.
    static func phrase(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) " + (count == 1 ? singular : plural)
    }
}

// MARK: - Liquid Glass

/// Applies Liquid Glass on iOS 26 and a material sheet everywhere else.
///
/// Used only on controls that float over scrolling content, never on cards that
/// scroll with the page. Call it *after* padding and layout modifiers so it wraps
/// the final laid-out shape.
struct PracticeFloatingGlass: ViewModifier {
    /// Corner radius fallback for the pre-26 material sheet.
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassCard()
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        }
    }
}

extension View {
    /// Floating control surface, glass where available.
    @ViewBuilder
    func practiceFloatingGlass(cornerRadius: CGFloat = Radius.card) -> some View {
        modifier(PracticeFloatingGlass(cornerRadius: cornerRadius))
    }
}

// MARK: - Shared small views

/// A labelled horizontal bar, used for per-level accuracy and for the topic rollup.
///
/// Presentation only: the value is handed in already graded or already measured.
struct PracticeMeter: View {
    let title: String
    let caption: String
    let value: Double
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(AppFont.display(15, .semibold))
                Spacer(minLength: Spacing.xs)
                Text(PracticeFormat.percent(value))
                    .font(AppFont.mono(13, .bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.16))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, min(1, value)) * proxy.size.width)
                }
            }
            .frame(height: 8)
            .animation(reduceMotion ? nil : Motion.Curve.decelerate, value: value)

            Text(caption)
                .font(AppFont.display(13, .regular))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(PracticeFormat.percent(value))
    }
}

/// A single row in the review list, showing what the item is and when it is next due.
struct ReviewItemRow: View {
    let item: ReviewItem
    let headline: String
    let detail: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: symbol).font(AppFont.body(.title3))
                .foregroundStyle(tint)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(AppFont.display(16, .semibold))
                    .lineLimit(2)
                Text(detail)
                    .font(AppFont.display(13, .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.xs)

            if item.isMastered {
                LevelPill(text: "Mastered")
            } else if item.lapses > 0 {
                LevelPill(text: "\(item.lapses) lapse\(item.lapses == 1 ? "" : "s")")
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to review this item")
    }

    private var symbol: String {
        switch item.source {
        case .exercise: "checkmark.bubble"
        case .vocabulary: "textformat.abc"
        case .lesson: "book.pages"
        }
    }

    private var tint: Color {
        if item.isMastered { return .success }
        if item.lapses > 0 { return .danger }
        return .brand
    }
}

/// The four buckets the review queue is filed into, exactly as `ReviewQueue` exposes them.
enum ReviewBucket: String, CaseIterable, Identifiable, Hashable {
    case dueToday
    case difficult
    case recentlyWrong
    case mastered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dueToday: "Due Today"
        case .difficult: "Difficult"
        case .recentlyWrong: "Recently Wrong"
        case .mastered: "Mastered"
        }
    }

    var caption: String {
        switch self {
        case .dueToday: "Ready right now"
        case .difficult: "Forgotten at least once"
        case .recentlyWrong: "Last answer was wrong"
        case .mastered: "Cleared the 21-day mark"
        }
    }

    var symbol: String {
        switch self {
        case .dueToday: "sun.horizon"
        case .difficult: "exclamationmark.triangle"
        case .recentlyWrong: "arrow.uturn.backward"
        case .mastered: "rosette"
        }
    }

    /// The items in this bucket. Delegated to `ReviewQueue`; the view never refilters.
    func items(in queue: ReviewQueue) -> [ReviewItem] {
        switch self {
        case .dueToday: queue.dueToday(on: Date())
        case .difficult: queue.difficult
        case .recentlyWrong: queue.recentlyWrong(limit: .max)
        case .mastered: queue.mastered
        }
    }
}
