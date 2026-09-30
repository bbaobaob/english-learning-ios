import SwiftUI
import EnglishCore
import EnglishStore

/// The spaced-repetition queue: the four buckets `ReviewQueue` exposes, one screen per
/// item, and a detail sheet that shows the learner the schedule behind their grade.
///
/// Rescheduling is one line and it belongs to the engine:
///
/// ```swift
/// store.upsertReview(SpacedRepetition().schedule(item, grade: grade))
/// ```
///
/// The view never adds a day to a due date. For a graded item the grade comes from
/// `SessionOutcome.wrongIDs`; for a flashcard or a re-teach it comes from the button
/// the learner pressed.
struct ReviewView: View {

    /// Pre-filters the queue to one topic; `nil` reviews everything.
    let topicID: String?

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var bucket: ReviewBucket = .dueToday
    @State private var activeItem: ReviewItem?
    @State private var detailItem: ReviewItem?

    private let repetition = SpacedRepetition()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                bucketPicker
                content
                Color.clear.frame(height: Spacing.xl)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
        }
        .background(PracticeBackdrop())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $activeItem) { item in
            ReviewItemView(item: item) { value in
                grade(item, value)
                activeItem = nil
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schedule", systemImage: "info.circle") { detailItem = item }
                }
            }
        }
        .sheet(item: $detailItem) { item in
            ReviewDetailSheet(item: item, repetition: repetition)
        }
    }

    // MARK: - Buckets

    private var bucketPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(
                title: "Queue",
                subtitle: topicID == nil ? "Everything the scheduler is tracking" : "Filtered to one skill",
                actionTitle: nil,
                action: nil
            )

            HStack(spacing: Spacing.sm) {
                ForEach(ReviewBucket.allCases) { candidate in
                    Button {
                        Haptics.selection()
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { bucket = candidate }
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(count(for: candidate))")
                                .font(AppFont.mono(18, .bold))
                                .monospacedDigit()
                            Text(candidate.title)
                                .font(AppFont.display(11, .semibold))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(bucket == candidate ? Color.brand : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            bucket == candidate ? Color.brand.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(candidate.title), \(count(for: candidate)) items")
                    .accessibilityAddTraits(bucket == candidate ? [.isSelected] : [])
                }
            }

            Text(bucket.caption)
                .font(AppFont.display(13, .regular))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if scopedItems.isEmpty {
            EmptyStateView(
                symbol: bucket == .mastered ? "rosette" : "checkmark.circle",
                title: emptyTitle,
                message: emptyMessage,
                actionTitle: emptyActionTitle,
                action: emptyAction
            )
        } else {
            summaryStrip
            ForEach(scopedItems) { item in
                Button {
                    Haptics.selection()
                    activeItem = item
                } label: {
                    ReviewItemRow(item: item, headline: headline(for: item), detail: detail(for: item))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Show schedule", systemImage: "info.circle") { detailItem = item }
                }
                .accessibilityAction(named: "Show schedule") { detailItem = item }
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: Spacing.md) {
            StatCard(
                title: "In this bucket",
                value: PracticeFormat.count(scopedItems.count),
                caption: bucket.title,
                symbol: bucket.symbol,
                tint: bucket == .mastered ? .success : .brand
            )
            StatCard(
                title: "Mastered",
                value: PracticeFormat.count(queue.mastered.count),
                caption: "21-day mark cleared",
                symbol: "rosette",
                tint: .success
            )
        }
    }

    // MARK: - Grading

    /// Reschedules one item and hands it to the store. The only write path in this file.
    private func grade(_ item: ReviewItem, _ value: SpacedRepetition.Grade) {
        Haptics.selection()
        appState.store.upsertReview(repetition.schedule(item, grade: value))
    }

    // MARK: - Reads

    /// Everything the store says is under review, wrapped so `ReviewQueue` can bucket it.
    ///
    /// ponytail: `ProgressStore.reviewQueue(on:)` already filters to due items, so
    /// `Difficult` and `Mastered` are faceted over the due set rather than the whole
    /// history. That is the frozen contract; if the buckets must span everything, add
    /// `ProgressStore.allReviewItems()` rather than reaching for the store's context.
    private var queue: ReviewQueue {
        ReviewQueue(appState.store.reviewQueue(on: Date()))
    }

    private var scopedItems: [ReviewItem] {
        let bucketed = bucket.items(in: queue)
        guard let topicID else { return bucketed }
        return bucketed.filter { $0.topicID == topicID }
    }

    private func count(for candidate: ReviewBucket) -> Int {
        let items = candidate.items(in: queue)
        guard let topicID else { return items.count }
        return items.filter { $0.topicID == topicID }.count
    }

    private var title: String {
        guard let topicID, let topic = appState.library.topic(topicID) else { return "Review" }
        return "Review · \(topic.title)"
    }

    private func headline(for item: ReviewItem) -> String {
        switch item.source {
        case .exercise:
            appState.library.exercise(item.refID)?.prompt ?? item.refID
        case .vocabulary:
            appState.library.vocabWord(item.refID)?.word ?? item.refID
        case .lesson:
            appState.library.lesson(item.refID)?.title ?? item.refID
        }
    }

    private func detail(for item: ReviewItem) -> String {
        let origin = item.topicID.flatMap { appState.library.topic($0)?.title } ?? "Mixed content"
        return origin + " · interval " + PracticeFormat.phrase(item.intervalDays, "day", "days")
    }

    // MARK: - The honest empty case

    private var emptyTitle: String {
        if queue.isEmpty { return "No reviews scheduled" }
        if topicID != nil { return "Nothing in this skill" }
        return "Nothing in \(bucket.title)"
    }

    private var emptyMessage: String {
        if queue.isEmpty {
            return "The queue fills up as you answer exercises. Anything you get wrong comes back today; "
                + "anything you get right returns tomorrow, then in three days, then further out."
        }
        if topicID != nil {
            return "This skill has nothing in the \(bucket.title.lowercased()) bucket. Try another bucket, or another skill."
        }
        return "This bucket is empty. Due Today is the one to work through — the other three are views onto the same items."
    }

    private var emptyActionTitle: String? {
        // Nothing scheduled at all: there is nowhere else to look, so no button.
        // Otherwise offer the one bucket that is worth working through.
        queue.isEmpty || bucket == .dueToday ? nil : "Show due today"
    }

    private var emptyAction: (() -> Void)? {
        guard emptyActionTitle != nil else { return nil }
        return {
            Haptics.selection()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { bucket = .dueToday }
        }
    }
}
