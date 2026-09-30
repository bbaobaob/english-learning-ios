import SwiftUI
import EnglishCore

/// A single-select or multi-select option list.
///
/// The option rows are buttons, not checkboxes, so VoiceOver announces
/// "selected" from the trait and the whole row is one tap target rather than a
/// small box inside a large row.
struct OptionListView: View {
    let items: [ExerciseItem]
    @Binding var selectedIDs: Set<String>
    let allowsMultiple: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(items) { item in
                OptionRow(
                    text: item.text ?? item.id,
                    isSelected: selectedIDs.contains(item.id),
                    allowsMultiple: allowsMultiple,
                    action: { toggle(item.id) }
                )
            }
        }
        .animation(Motion.accessible(Motion.quick, reduceMotion: reduceMotion), value: selectedIDs)
    }

    private func toggle(_ id: String) {
        Haptics.selection()
        if allowsMultiple {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
        } else {
            // A single-select tap on the already-selected option clears it,
            // which is the only way to un-answer a question by tapping.
            selectedIDs = selectedIDs == [id] ? [] : [id]
        }
    }
}

private struct OptionRow: View {
    let text: String
    let isSelected: Bool
    let allowsMultiple: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: marker)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? Palette.surface : Palette.textTertiary)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                Text(text)
                    .font(AppFont.body(.body))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(Spacing.md)
            .frame(minHeight: Metric.tapTarget)
            .background(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(isSelected ? Palette.brandSoft : Palette.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .strokeBorder(
                        isSelected ? Palette.brand : Palette.separator,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityHint(
            Text(verbatim: allowsMultiple ? "Double tap to select or deselect." : "Double tap to select.")
        )
    }

    private var marker: String {
        if allowsMultiple {
            return isSelected ? "checkmark.square.fill" : "square"
        }
        return isSelected ? "largecircle.fill.circle" : "circle"
    }
}

/// The true/false pair. Two full-width buttons rather than a switch: the
/// learner is committing to an answer, and a switch invites a half-change.
struct BooleanPairView: View {
    @Binding var selection: Bool?

    var body: some View {
        HStack(spacing: Spacing.md) {
            BooleanOption(
                title: "True",
                symbol: "checkmark.circle",
                isSelected: selection == true,
                tint: Palette.success
            ) {
                Haptics.selection()
                selection = selection == true ? nil : true
            }

            BooleanOption(
                title: "False",
                symbol: "xmark.circle",
                isSelected: selection == false,
                tint: Palette.danger
            ) {
                Haptics.selection()
                selection = selection == false ? nil : false
            }
        }
    }
}

private struct BooleanOption: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                Image(systemName: symbol)
                    .font(.title2)
                    .accessibilityHidden(true)
                Text(title)
                    .font(AppFont.display(.headline))
            }
            .foregroundStyle(isSelected ? Palette.surface : tint)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(isSelected ? tint : tint.opacity(0.14))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(Text(verbatim: title))
    }
}

/// The free-text answer field.
///
/// Multiline and Dynamic Type aware: at the accessibility text sizes a
/// single-line field clips the answer, which is worse than a taller field.
struct TextAnswerField: View {
    @Binding var text: String
    let prompt: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        TextField(
            "",
            text: $text,
            axis: .vertical
        )
        .font(AppFont.body(.body))
        .foregroundStyle(Palette.textPrimary)
        .lineLimit(1...6)
        .padding(Spacing.md)
        .frame(minHeight: Metric.buttonHeight)
        .background(
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .fill(Palette.field)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .strokeBorder(Palette.separator, lineWidth: 1)
        )
        .focused(isFocused)
        .submitLabel(.done)
        .accessibilityLabel(Text(verbatim: prompt))
        .accessibilityHint(Text(verbatim: "Double tap to type your answer."))
    }
}
