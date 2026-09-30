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
                Image(systemName: symbol)
                    .font(.footnote.weight(.bold))
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
            Image(systemName: "flame.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isActive ? Palette.streak : Palette.textTertiary)
                .symbolEffect(
                    .bounce,
                    options: .nonRepeating,
                    value: isActive ? days : -1
                )
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
            Image(systemName: "bolt.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.xp)
                .accessibilityHidden(true)
            Text(Format.count(xp))
                .font(AppFont.mono(.caption, weight: .bold))
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
struct Chip: View {
    let text: String
    let isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
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
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
