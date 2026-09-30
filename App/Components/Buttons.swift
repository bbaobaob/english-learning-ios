import SwiftUI

/// The one filled, brand-coloured button in the app. One per screen at most.
///
/// It fills its width so the tap target is unambiguous on a phone, and its
/// height grows with Dynamic Type rather than clipping the label.
struct PrimaryButton: View {
    let title: String
    let symbol: String?
    /// Disabled state. A disabled primary button drops to 40% opacity rather
    /// than greying out, so it still reads as the same button.
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if let symbol {
                    Image(systemName: symbol)
                        .imageScale(.medium)
                }
                Text(title)
                    .font(AppFont.display(.headline))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: Metric.buttonHeight)
            .padding(.horizontal, Spacing.lg)
            .foregroundStyle(Palette.surface)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Palette.brand)
            )
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!isEnabled)
        .animation(Motion.accessible(Motion.quick, reduceMotion: reduceMotion), value: isEnabled)
        .accessibilityLabel(title)
        .accessibilityHint(Text(verbatim: "Double tap to continue."))
        .accessibilityAddTraits(.isButton)
    }
}

/// Press feedback for ``PrimaryButton``: a small, uniform scale-down. No
/// bounce, no colour shift — a bounce on a wide full-width button looks like a
/// glitch, not an interaction.
private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(Motion.accessible(Motion.quick, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// The outline button. Used for a secondary action that sits beside a primary
/// one, or alone when there is no primary action.
struct SecondaryButton: View {
    let title: String
    let symbol: String?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
                    .font(AppFont.display(.subheadline))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: Metric.buttonHeight)
            .padding(.horizontal, Spacing.lg)
            .foregroundStyle(Palette.brand)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Palette.brandSoft)
            )
        }
        .buttonStyle(PrimaryButtonStyle())
        .animation(Motion.accessible(Motion.quick, reduceMotion: reduceMotion), value: reduceMotion)
        .accessibilityLabel(title)
        .accessibilityHint(Text(verbatim: "Double tap to continue."))
        .accessibilityAddTraits(.isButton)
    }
}

/// A compact icon-only control sized to the 44pt minimum tap target, with its
/// hit area padded out so the glyph itself can stay small.
struct IconButton: View {
    let symbol: String
    let label: String
    var isActive: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(isActive ? Palette.brand : Palette.textSecondary)
                .frame(width: Metric.tapTarget, height: Metric.tapTarget)
                .background(
                    Circle().fill(isActive ? Palette.brandSoft : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .animation(Motion.accessible(Motion.quick, reduceMotion: reduceMotion), value: isActive)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}
