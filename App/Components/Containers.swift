import SwiftUI

/// The heading that opens a section of a scrolling screen, with an optional
/// trailing action.
///
/// The title and subtitle combine into one VoiceOver element; the action stays
/// separate, because folding a button into its own label is the classic way to
/// make an action unreachable.
struct SectionHeader: View {
    let title: String
    let subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(AppFont.display(.title3))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.body(.subheadline))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: Spacing.md)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: Spacing.xs) {
                        Text(actionTitle)
                            .font(AppFont.body(.subheadline, weight: .semibold))
                        Image(systemName: "chevron.right").font(AppFont.body(.caption2, weight: .bold))
                    }
                    .foregroundStyle(Palette.brand)
                    .frame(minHeight: Metric.tapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: actionTitle))
                .accessibilityHint(Text(verbatim: "Double tap to open."))
            }
        }
    }
}

/// A topic in a list: icon, title, summary, level, and a progress bar.
///
/// The whole card is one button. `accessibilityElement(children: .combine)`
/// plus an explicit label means VoiceOver reads the topic as a single thing
/// with its progress attached, instead of as six unlabelled fragments.
struct TopicCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let progress: Double
    let level: String
    let isCompleted: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double {
        progress.isFinite ? min(max(progress, 0), 1) : 0
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                            .fill(isCompleted ? Palette.success.opacity(0.16) : Palette.brandSoft)
                        Image(systemName: isCompleted ? "checkmark" : symbol).font(AppFont.body(.title3, weight: .semibold))
                            .foregroundStyle(isCompleted ? Palette.success : Palette.brand)
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(title)
                            .font(AppFont.display(.headline))
                            .foregroundStyle(Palette.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(subtitle)
                            .font(AppFont.body(.subheadline))
                            .foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: Spacing.md) {
                    LevelPill(text: level)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.field)
                            Capsule()
                                .fill(isCompleted ? Palette.success : Palette.brand)
                                .frame(width: proxy.size.width * clamped)
                        }
                    }
                    .frame(height: 6)
                    .accessibilityHidden(true)

                    Text(Format.percent(clamped))
                        .font(AppFont.mono(.caption, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
            .cardStyle()
        }
        .buttonStyle(TopicCardButtonStyle(reduceMotion: reduceMotion))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
        .accessibilityValue(Text(verbatim: Format.percent(clamped)))
        .accessibilityHint(Text(verbatim: isCompleted ? "Completed. Double tap to review." : "Double tap to start."))
    }

    private var accessibilityLabel: String {
        isCompleted ? "\(title), completed, \(level)" : "\(title), \(level)"
    }
}

/// A press-in response for ``TopicCard``. The card lifts slightly rather than
/// scaling, because a full-width card scaled down looks like it is being
/// dismissed.
private struct TopicCardButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.accessible(Motion.quick, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// Shown when a list has nothing in it yet. Deliberately not an error state:
/// an empty vocab deck and a failed network fetch look nothing alike, and
/// mixing them teaches the user that a real problem is harmless.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Palette.brand.opacity(0.7))
                .accessibilityHidden(true)

            Text(title)
                .font(AppFont.display(.title3))
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(AppFont.body(.subheadline))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, symbol: nil, action: action)
                    .padding(.top, Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .padding(.horizontal, Spacing.lg)
        .accessibilityElement(children: .combine)
    }
}

/// A dismissible, actionable failure notice.
///
/// This is the app's only inline error surface. Content-loading failures route
/// here rather than to a crash, so a malformed `content.json` is a banner the
/// learner can retry past rather than a launch they cannot get out of.
struct ErrorBanner: View {
    let message: String
    let retry: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill").font(AppFont.body(.subheadline))
                .foregroundStyle(Palette.danger)
                .accessibilityHidden(true)

            Text(message)
                .font(AppFont.body(.subheadline))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let retry {
                Button(action: retry) {
                    Text("Retry")
                        .font(AppFont.body(.subheadline, weight: .semibold))
                        .foregroundStyle(Palette.danger)
                        .frame(minHeight: Metric.tapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: "Retry"))
                .accessibilityHint(Text(verbatim: "Double tap to try loading again."))
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.dangerSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.danger.opacity(0.35), lineWidth: 1)
        )
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -8)
        .onAppear {
            withAnimation(Motion.accessible(Motion.standard, reduceMotion: reduceMotion)) {
                isVisible = true
            }
        }
        .accessibilityElement(children: .contain)
    }
}
