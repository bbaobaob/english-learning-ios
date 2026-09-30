import SwiftUI
import EnglishCore

/// A two-column tap-to-pair grid.
///
/// **Why tap-to-pair and not two draggable lists.** Drag-and-drop matching is
/// the interaction nobody can do with VoiceOver or Switch Control, and this app
/// has to be fully operable without a drag gesture. The tap-to-pair version
/// also happens to be faster on a phone: the first tap is precise, the second
/// is on a target twice as large as a drag handle.
///
/// The flow: tap a word in the left column, it highlights, then tap its match
/// in the right column and the pair is locked and shown joined. Tapping a
/// locked pair unlocks it, so a mistake is one tap to undo rather than a
/// restart.
struct MatchingGridView: View {
    let items: [ExerciseItem]
    /// Item id to the key it is matched to.
    @Binding var pairs: [String: String]
    /// The left-column item awaiting a match, if any.
    @Binding var focusedID: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Left column: every item, in content order. The answer is a map from item
    /// id to `matchKey`, so the items themselves are the left side.
    private var leftItems: [ExerciseItem] { items }

    /// Right column: the distinct `matchKey` values, sorted so the grid is
    /// stable between launches. Content authors pick the ordering that makes
    /// sense pedagogically; shuffling it here would make a screenshot-based
    /// review of the content useless.
    private var rightKeys: [String] {
        Array(Set(items.compactMap(\.matchKey))).sorted()
    }

    private var allPaired: Bool { pairs.count == leftItems.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if allPaired {
                // The instruction says the grid is done; say so in the same
                // place rather than relying on a colour change the learner has
                // to notice.
                Label("All pairs matched", systemImage: "checkmark.circle.fill")
                    .font(AppFont.body(.caption, weight: .semibold))
                    .foregroundStyle(Palette.success)
            } else {
                Text(focusedLabel().map { "\($0) — now tap its match." } ?? "Tap a word, then tap its match.")
                    .font(AppFont.body(.caption))
                    .foregroundStyle(Palette.textSecondary)
            }

            // Two columns side by side. Not a `Grid`: the columns have
            // different lengths (items vs distinct keys) and there is no
            // meaningful row correspondence between them — a `Grid` would
            // imply a row pairing that does not exist.
            HStack(alignment: .top, spacing: Spacing.sm) {
                VStack(spacing: Spacing.sm) {
                    ForEach(leftItems) { item in
                        leftCell(item)
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: Spacing.sm) {
                    ForEach(rightKeys, id: \.self) { key in
                        rightCell(for: key)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func leftCell(_ item: ExerciseItem) -> some View {
        let isFocused = focusedID == item.id
        let isPaired = pairs[item.id] != nil
        return MatchChip(
            text: item.text ?? item.id,
            isSelected: isFocused,
            isPaired: isPaired,
            tint: isPaired ? Palette.success : Palette.brand
        ) {
            Haptics.selection()
            // Tapping a paired item un-pairs it, and focuses it, so the next
            // tap completes the correction rather than starting over.
            if isPaired {
                pairs.removeValue(forKey: item.id)
            }
            focusedID = item.id
        }
        .animation(Motion.accessible(Motion.quick, reduceMotion: reduceMotion), value: isPaired)
    }

    private func rightCell(for key: String) -> some View {
        // The item this key is currently paired to, if any. Read back from
        // `pairs` rather than from the item's own `matchKey`, because the
        // content's `matchKey` *is* the answer and reading it here would paint
        // the solution onto the grid.
        let owner = leftItems.first { item in pairs[item.id] == key }

        return MatchChip(
            text: key,
            // A paired key highlights itself rather than its owner, because the
            // learner's attention is on the key they just tapped.
            isSelected: owner != nil,
            isPaired: owner != nil,
            tint: Palette.success,
            action: {
                guard let owner, isAvailable(key: key) else { return }
                Haptics.selection()
                pairs[owner.id] = key
                focusedID = nil
            }
        )
        .opacity(isAvailable(key: key) ? 1 : 0.4)
        .allowsHitTesting(isAvailable(key: key))
    }

    /// A key can be tapped only while some item is focused, and only if no
    /// other item already holds it. A key is the right-hand side of exactly
    /// one pair, so allowing two would produce a silently wrong answer.
    private func isAvailable(key: String) -> Bool {
        guard let focusedID else { return false }
        let alreadyOwned = pairs.first { $0.value == key && $0.key != focusedID }
        return alreadyOwned == nil
    }

    /// The label of the focused item, for the status line.
    ///
    /// Deliberately the item's *text* and never its `matchKey`: the match key
    /// is the answer, and printing it under the grid would hand over the
    /// solution the moment the learner tapped the first word.
    private func focusedLabel() -> String? {
        guard let focusedID, let item = leftItems.first(where: { $0.id == focusedID }) else { return nil }
        return item.text ?? item.id
    }
}

private struct MatchChip: View {
    let text: String
    let isSelected: Bool
    let isPaired: Bool
    let tint: Color
    /// `nil` when the chip is not currently tappable, e.g. a key that is
    /// already spoken for. Such a chip is still a labelled, readable element —
    /// it just is not announced as a button, because activating it would do
    /// nothing.
    let action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) { label }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            } else {
                label
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityValue(Text(verbatim: isPaired ? "Matched" : isSelected ? "Selected" : "Not matched"))
        .accessibilityHint(
            Text(verbatim: action == nil ? "Already used for another word." : "Double tap to select, then tap its match.")
        )
    }

    private var label: some View {
        Text(text)
            .font(AppFont.body(.subheadline, weight: isPaired ? .semibold : .regular))
            .foregroundStyle(isPaired ? Palette.success : isSelected ? Palette.surface : Palette.textPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: Metric.tapTarget)
            .padding(.horizontal, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .strokeBorder(border, lineWidth: isSelected || isPaired ? 1.5 : 1)
            )
            .contentShape(Rectangle())
    }

    private var fill: Color {
        if isPaired { return Palette.success.opacity(0.16) }
        if isSelected { return tint }
        return Palette.field
    }

    private var border: Color {
        if isPaired { return Palette.success }
        if isSelected { return tint }
        return Palette.separator
    }
}

/// A word-ordering list that can be reordered three ways.
///
/// 1. **Drag** — the familiar gesture, via a long-press-and-move handle.
/// 2. **Move up / move down buttons** — always present, so the list is fully
///    operable with Switch Control, VoiceOver, or a motor impairment that makes
///    dragging unreliable.
/// 3. **VoiceOver actions** — `.accessibilityAction(named:)` on each row, so
///    the reorder is reachable from the rotor without tabbing through two extra
///    buttons per row.
///
/// Only the drag is optional. The buttons are the accessible baseline, not a
/// fallback bolted on afterwards.
struct ReorderWordsView: View {
    @Binding var tokens: [String]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if tokens.isEmpty {
                Text("All words are used.")
                    .font(AppFont.body(.caption))
                    .foregroundStyle(Palette.textTertiary)
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                        row(index: index, token: token)
                    }
                }
            }

            if tokens.count > 1 {
                HStack {
                    Text("Tap the arrows to move a word.")
                        .font(AppFont.body(.caption))
                        .foregroundStyle(Palette.textTertiary)
                    Spacer()
                    Button {
                        Haptics.selection()
                        tokens.removeAll()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(AppFont.body(.caption, weight: .semibold))
                            .foregroundStyle(Palette.brand)
                            .frame(minHeight: Metric.tapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: "Reset the word order"))
                }
            }
        }
    }

    private func row(index: Int, token: String) -> some View {
        HStack(spacing: Spacing.md) {
            Text("\(index + 1)")
                .font(AppFont.mono(.caption, weight: .bold))
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 24, alignment: .trailing)
                .accessibilityHidden(true)

            Text(token)
                .font(AppFont.body(.body))
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            // The accessible reorder path. Two 44pt targets per row, which is
            // a lot of chrome, so they are tinted down to a hairline circle
            // and only take the tint's colour when enabled.
            moveButton(symbol: "chevron.up", index: index, delta: -1)
            moveButton(symbol: "chevron.down", index: index, delta: 1)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(minHeight: Metric.tapTarget)
        .background(
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .fill(Palette.field)
        )
        // The drag gesture. `.draggable` rather than `onDrag` because SwiftUI's
        // own reordering is a list-level behaviour and these rows live in a
        // `VStack`.
        .draggable(token) {
            Text(token)
                .font(AppFont.body(.body))
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                        .fill(Palette.surfaceRaised)
                )
        }
        .dropDestination(for: String.self) { dropped, _ in
            move(index: index, to: indexOf(dropped))
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "Word \(index + 1) of \(tokens.count): \(token)"))
        .accessibilityAction(named: "Move earlier") { move(index: index, to: index - 1) }
        .accessibilityAction(named: "Move later") { move(index: index, to: index + 1) }
        .animation(Motion.accessible(Motion.quick, reduceMotion: reduceMotion), value: tokens)
    }

    private func moveButton(symbol: String, index: Int, delta: Int) -> some View {
        let target = index + delta
        let isEnabled = tokens.indices.contains(target)
        return Button {
            move(index: index, to: target)
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(isEnabled ? Palette.brand : Palette.textTertiary.opacity(0.4))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(verbatim: delta < 0 ? "Move \(tokens[index]) earlier" : "Move \(tokens[index]) later"))
        .accessibilityAddTraits(.isButton)
    }

    /// Moves the token at `index` to `destination`, ignoring out-of-range
    /// requests. A drag that lands on the current position is a no-op, not a
    /// crash.
    private func move(index: Int, to destination: Int) {
        guard tokens.indices.contains(index), tokens.indices.contains(destination) else { return }
        guard index != destination else { return }
        Haptics.selection()
        let token = tokens.remove(at: index)
        tokens.insert(token, at: destination)
    }

    private func indexOf(_ token: String) -> Int {
        tokens.firstIndex(of: token) ?? 0
    }
}
