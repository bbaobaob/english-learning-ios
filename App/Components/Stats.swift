import SwiftUI

/// A labelled number: title above, value large, optional caption below.
///
/// The value uses the display face at `.title` so a row of `StatCard`s reads as
/// a row of figures rather than a wall of body text, and the tabular figure
/// style means neighbouring numbers align on their digits.
struct StatCard: View {
    let title: String
    let value: String
    let caption: String?
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: symbol).font(AppFont.body(.footnote, weight: .bold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(AppFont.body(.subheadline))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(value)
                .font(AppFont.display(.title, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let caption {
                Text(caption)
                    .font(AppFont.body(.caption))
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        // One combined element: VoiceOver reads "Streak, 7 days, longest 12"
        // instead of walking three separate fragments.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
    }

    private var accessibilityLabel: String {
        var parts = [title, value]
        if let caption { parts.append(caption) }
        return parts.joined(separator: ", ")
    }
}

/// A circular progress indicator, optionally with a label in the middle.
///
/// Drawn with two `Circle` strokes rather than a canvas: it stays legible at
/// the largest accessibility text sizes, and it inherits the environment's
/// colour and shape behaviour for free.
struct ProgressRing: View {
    /// Completion in `0...1`. Values outside the range are clamped.
    let progress: Double
    var lineWidth: CGFloat = 8
    var tint: Color = Palette.brand
    var label: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double {
        progress.isFinite ? min(max(progress, 0), 1) : 0
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.field, style: StrokeStyle(lineWidth: lineWidth))
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                // The trim animates from the previous value only, so the ring
                // grows when progress arrives rather than on first layout.
                .rotationEffect(.degrees(-90))
                .animation(Motion.accessible(Motion.standard, reduceMotion: reduceMotion), value: clamped)

            if let label {
                Text(label)
                    .font(AppFont.mono(.headline, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(Spacing.xs)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(verbatim: Format.percent(clamped)))
        .accessibilityLabel(Text(verbatim: "Progress"))
    }
}

/// The streak flame. `isActive == false` dims the flame without hiding the
/// number, so a broken streak still reads as a streak rather than as nothing.
struct StreakFlame: View {
    let days: Int
    var isActive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // The flame's behaviour *is* the streak's information: `StreakEmber`
            // is barely alive below three days and settles above it, so a
            // one-day streak stops looking like a thirty-day one. It is
            // decorative, so it is hidden — the label below carries the meaning.
            StreakEmber(days: isActive ? days : 0, isActive: isActive, size: 20)
                .accessibilityHidden(true)
            Text("\(days)")
                .font(AppFont.mono(.subheadline, weight: .bold))
                .foregroundStyle(isActive ? Palette.textPrimary : Palette.textSecondary)
        }
        .padding(.horizontal, Spacing.sm)
        .frame(minHeight: Metric.controlHeight)
        .background(
            Capsule().fill(isActive ? Palette.streak.opacity(0.14) : Palette.field)
        )
        .animation(Motion.accessible(Motion.quick, reduceMotion: reduceMotion), value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Streak: \(days) \(days == 1 ? "day" : "days")"))
    }
}

/// A compact XP pill. Uses tabular figures so the number does not shift the
/// pill's width as it counts up.
struct XPBadge: View {
    let xp: Int

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "bolt.fill").font(AppFont.body(.caption, weight: .bold))
                .foregroundStyle(Palette.xp)
                .accessibilityHidden(true)
            // Rolls to the new total instead of swapping it. A badge that jumps from
            // 1,200 to 1,250 reads as an edit; one that rolls reads as progress,
            // which is the whole reason the learner looks at it.
            CountUpNumber(
                value: xp,
                textStyle: .caption,
                weight: .bold,
                usesGrouping: true,
                accessibilityLabel: "\(Format.count(xp)) experience points"
            )
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Capsule().fill(Palette.xp.opacity(0.14)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(xp) experience points"))
    }
}

/// A small rounded label, used for a lesson's level and for topic categories.
struct LevelPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppFont.body(.caption2, weight: .semibold))
            .foregroundStyle(Palette.textSecondary)
            .textCase(.uppercase)
            .lineLimit(1)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                Capsule().fill(Palette.field)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "Level: \(text)"))
    }
}

/// A selectable filter chip.
///
/// Two ways to use it:
///
/// * `Chip(text:isSelected:action:)` — tappable. The chip owns the button, so it
///   gets the tap highlight, the accessibility traits, and the minimum tap
///   target without the caller wrapping it.
/// * `Chip(text:isSelected:)` — presentational, for a chip that sits inside a
///   row that is *already* one button. Wrapping a non-action chip in a `Button`
///   nests a button in a button, which VoiceOver reads as two stops for one row.
struct Chip: View {
    let text: String
    let isSelected: Bool
    /// Optional leading symbol name, set only by the action-carrying initialiser.
    private let symbol: String?
    /// `nil` when the chip is presentational rather than tappable.
    private let action: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A chip the learner can tap.
    init(text: String, isSelected: Bool, action: @escaping () -> Void) {
        self.text = text
        self.isSelected = isSelected
        self.symbol = nil
        self.action = action
    }

    /// A chip the learner can tap, with a leading symbol.
    ///
    /// The symbol is `accessibilityHidden`, so the chip is still announced as
    /// just its text — a filter chip that says "All topics" must not be read
    /// out as "line-through-three-dots-lines, All topics".
    init(text: String, symbol: String?, isSelected: Bool, action: @escaping () -> Void) {
        self.text = text
        self.isSelected = isSelected
        self.symbol = symbol
        self.action = action
    }

    /// A chip that only *looks* interactive. Use inside an existing button.
    init(text: String, isSelected: Bool) {
        self.text = text
        self.isSelected = isSelected
        self.symbol = nil
        self.action = nil
    }

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(AppFont.body(.caption2))
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(AppFont.body(.subheadline, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? Palette.surface : Palette.textSecondary)
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: Metric.controlHeight)
        .background(
            Capsule().fill(isSelected ? Palette.brand : Palette.field)
        )
        .overlay(
            Capsule().strokeBorder(
                isSelected ? Color.clear : Palette.separator,
                lineWidth: 1
            )
        )
        .animation(Motion.accessible(Motion.quick, reduceMotion: reduceMotion), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
