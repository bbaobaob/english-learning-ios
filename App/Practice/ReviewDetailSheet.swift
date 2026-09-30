import SwiftUI
import EnglishCore

/// Shows the learner the schedule behind one review item: its next due date, its current
/// ease and interval, and what each grade would do to it.
///
/// Every number here is produced by `SpacedRepetition.schedule(_:grade:)`. The sheet
/// adds a day to nothing.
struct ReviewDetailSheet: View {

    let item: ReviewItem
    let repetition: SpacedRepetition

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    current

                    SectionHeader(
                        title: "If you graded it now",
                        subtitle: "The scheduler's own answer for each button",
                        actionTitle: nil,
                        action: nil
                    )

                    VStack(spacing: Spacing.sm) {
                        ForEach(Self.previews, id: \.0) { preview in
                            previewRow(preview)
                        }
                    }

                    Text("The item comes back when its due date arrives, and it counts as mastered once "
                         + "`ReviewItem.isMastered` says so: a long interval and several correct reviews in a row.")
                        .font(AppFont.display(13, .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Color.clear.frame(height: Spacing.lg)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
            }
            .background(PracticeBackdrop())
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var current: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: item.isMastered ? "rosette" : "calendar.badge.clock")
                    AppFont.body(.title2)
                    .foregroundStyle(item.isMastered ? Color.success : Color.brand)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.isMastered ? "Mastered" : "In the queue")
                        .font(AppFont.display(20, .bold))
                    Text(item.dueDate, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(AppFont.display(14, .regular))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: Spacing.md) {
                StatCard(
                    title: "Interval",
                    value: PracticeFormat.phrase(item.intervalDays, "day", "days"),
                    caption: "current step",
                    symbol: "arrow.left.arrow.right",
                    tint: .brand
                )
                StatCard(
                    title: "Ease",
                    value: PracticeFormat.ease(item.ease),
                    caption: "floor is \(PracticeFormat.ease(SpacedRepetition.minimumEase))",
                    symbol: "gauge.medium",
                    tint: .accuracy
                )
            }

            HStack(spacing: Spacing.md) {
                StatCard(
                    title: "In a row",
                    value: PracticeFormat.count(item.repetitions),
                    caption: "successful reviews",
                    symbol: "arrow.up.forward",
                    tint: .success
                )
                StatCard(
                    title: "Lapses",
                    value: PracticeFormat.count(item.lapses),
                    caption: "times forgotten",
                    symbol: "arrow.uturn.backward",
                    tint: item.lapses > 0 ? .danger : .secondary
                )
            }

            Text("Added \(item.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(AppFont.display(12, .regular))
                .foregroundStyle(.tertiary)
        }
    }

    private func previewRow(_ preview: Preview) -> some View {
        let next = repetition.schedule(item, grade: preview.grade)

        return HStack(spacing: Spacing.md) {
            Image(systemName: preview.symbol)
                AppFont.body(.title3)
                .foregroundStyle(preview.tint)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(preview.title)
                    .font(AppFont.display(15, .semibold))
                Text("ease \(PracticeFormat.ease(next.ease)) · \(PracticeFormat.phrase(next.repetitions, "review", "reviews")) in a row")
                    .font(AppFont.mono(12, .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Spacing.xs)

            VStack(alignment: .trailing, spacing: 1) {
                Text(next.intervalDays == 0 ? "Today" : "+\(next.intervalDays)d")
                    .font(AppFont.mono(14, .bold))
                    .foregroundStyle(preview.tint)
                Text(next.dueDate.formatted(date: .abbreviated, time: .omitted))
                    .font(AppFont.display(11, .regular))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private struct Preview {
        let grade: SpacedRepetition.Grade
        let title: String
        let symbol: String
        let tint: Color
    }

    private static let previews: [Preview] = [
        Preview(grade: .again, title: "Again", symbol: "arrow.uturn.backward", tint: .danger),
        Preview(grade: .hard, title: "Hard", symbol: "tortoise", tint: .warning),
        Preview(grade: .good, title: "Good", symbol: "checkmark", tint: .brand),
        Preview(grade: .easy, title: "Easy", symbol: "arrow.up.forward", tint: .success),
    ]
}
