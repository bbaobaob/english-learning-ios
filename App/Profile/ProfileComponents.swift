import SwiftUI
import EnglishStore

// Small building blocks the Profile screen composes. Each one is dumb on
// purpose: the numbers arrive already computed in `ProfileModel`.

// MARK: - Study heat map

/// A month of study days coloured by minutes studied.
struct StudyHeatMap: View {

    let month: ProfileModel.HeatMapMonth

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Five buckets rather than a continuous scale: at this cell size the
    /// difference between 20 and 25 minutes is invisible, and pretending
    /// otherwise would make the map lie.
    private func intensity(for day: StudyDay) -> Int {
        switch day.minutes {
        case 0: 0
        case 1..<10: 1
        case 10..<20: 2
        case 20..<40: 3
        default: 4
        }
    }

    private func color(for level: Int) -> Color {
        switch level {
        case 0: Color.secondary.opacity(0.12)
        case 1: Color.brand.opacity(0.3)
        case 2: Color.brand.opacity(0.5)
        case 3: Color.brand.opacity(0.75)
        default: Color.brand
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(month.title)
                    .font(AppFont.display(.subheadline, weight: .semibold))
                Spacer()
                Text("less → more")
                    .font(AppFont.display(.caption2, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(month.days) { day in
                    let level = intensity(for: day)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color(for: level))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            Text("\(Calendar.current.component(.day, from: day.day))")
                                .font(AppFont.mono(.caption2, weight: .medium))
                                .foregroundStyle(level >= 3 ? Color.white : Color.primary.opacity(0.7))
                        }
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: level)
                        .accessibilityElement()
                        .accessibilityLabel("\(day.day.formatted(date: .complete, time: .omitted)), \(day.minutes) minutes studied")
                }
            }

            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color(for: level))
                        .frame(width: 14, height: 14)
                }
                Text(minutesSummary)
                    .font(AppFont.display(.caption, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.lg)
        .cardStyle()
    }

    private var minutesSummary: String {
        let total = month.days.reduce(0) { $0 + $1.minutes }
        let active = month.days.filter { $0.minutes > 0 }.count
        guard active > 0 else { return "No study recorded" }
        return "\(total) min across \(active) day\(active == 1 ? "" : "s")"
    }
}

// MARK: - Skill row

/// One skill: a ring, a percentage, and the numbers behind it.
struct SkillProgressRow: View {

    let skill: ProfileModel.SkillProgress

    var body: some View {
        HStack(spacing: Spacing.md) {
            ProgressRing(
                progress: skill.progress ?? 0,
                lineWidth: 4,
                tint: skill.progress == nil ? Color.secondary.opacity(0.4) : Color.brand,
                label: skill.progress.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
            )
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.title)
                    .font(AppFont.display(.body, weight: .medium))
                    .foregroundStyle(.primary)
                Text(skill.detail)
                    .font(AppFont.display(.caption, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Spacing.sm)

            Image(systemName: skill.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            skill.progress == nil
                ? "\(skill.title). \(skill.detail)."
                : "\(skill.title), \(Int(((skill.progress ?? 0) * 100).rounded())) percent. \(skill.detail)."
        )
    }
}

// MARK: - 14 day chart

/// Minutes studied per day for the last fourteen days, as a bar row.
struct Last14DaysChart: View {

    let days: [StudyDay]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var peak: Int {
        max(1, days.map(\.minutes).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Last 14 days")
                    .font(AppFont.display(.subheadline, weight: .semibold))
                Spacer()
                Text("\(days.reduce(0) { $0 + $1.minutes }) min")
                    .font(AppFont.mono(.caption, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(days) { day in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(day.minutes == 0 ? Color.secondary.opacity(0.15) : Color.brand.gradient)
                            .frame(height: max(4, CGFloat(day.minutes) / CGFloat(peak) * 64))
                            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8), value: day.minutes)

                        Text(day.day.formatted(.dateTime.day()))
                            .font(AppFont.mono(.system(size: 9), weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement()
                    .accessibilityLabel("\(day.day.formatted(date: .abbreviated, time: .omitted)), \(day.minutes) minutes")
                }
            }
        }
        .padding(Spacing.lg)
        .cardStyle()
    }
}

// MARK: - Weak area

/// One ranked weak topic.
struct WeakAreaRow: View {

    let area: ProfileModel.WeakArea

    var body: some View {
        HStack(spacing: Spacing.md) {
            ProgressRing(
                progress: area.accuracy,
                lineWidth: 4,
                tint: area.accuracy < 0.5 ? Color.danger : Color.warning,
                label: "\(Int((area.accuracy * 100).rounded()))"
            )
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(area.title)
                    .font(AppFont.display(.body, weight: .medium))
                    .foregroundStyle(.primary)
                Text("\(area.missed) of \(area.done) wrong")
                    .font(AppFont.display(.caption, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Spacing.sm)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.sm)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens practice for this topic")
    }
}

// MARK: - Achievement

/// One badge, locked or unlocked.
struct AchievementTile: View {

    let badge: ProfileModel.AchievementBadge

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: badge.isUnlocked ? badge.symbol : "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(badge.isUnlocked ? Color.xp : Color.secondary.opacity(0.5))
                    .accessibilityHidden(true)
                Spacer()
                if !badge.isUnlocked {
                    Text("\(badge.value)/\(badge.threshold)")
                        .font(AppFont.mono(.caption2, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(badge.title)
                .font(AppFont.display(.subheadline, weight: .semibold))
                .foregroundStyle(badge.isUnlocked ? Color.primary : Color.secondary)
                .lineLimit(2)

            Text(badge.isUnlocked ? (badge.unlockedAt.map { "Earned \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Earned") : badge.detail)
                .font(AppFont.display(.caption2, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !badge.isUnlocked {
                ProgressView(value: badge.progress)
                    .tint(Color.secondary.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(badge.isUnlocked ? AnyShapeStyle(Color.xp.opacity(0.08)) : AnyShapeStyle(Color.secondary.opacity(0.06)), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(badge.isUnlocked ? Color.xp.opacity(0.35) : Color.secondary.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            badge.isUnlocked
                ? "\(badge.title), earned. \(badge.detail)."
                : "\(badge.title), locked. \(badge.detail). \(badge.value) of \(badge.threshold)."
        )
    }
}

// MARK: - Notification row

/// A toggle plus a delivery time for one notification family.
///
/// The row holds the draft value locally and reports changes upward; the parent
/// owns the store write and the permission prompt.
struct NotificationRow: View {

    let kind: NotificationKind
    let isEnabled: Bool
    let hour: Int
    let minute: Int
    let onChange: (Bool, Int, Int) -> Void

    @State private var enabled: Bool = false
    @State private var time: Date = Date()

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Image(systemName: Self.symbol(for: kind))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                Text(Self.title(for: kind))
                    .font(AppFont.display(.body, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: Spacing.sm)

                Toggle(Self.title(for: kind), isOn: $enabled)
                    .labelsHidden()
                    .accessibilityLabel(Self.title(for: kind))
            }
            .onChange(of: enabled) { _, newValue in
                // Fires only from a tap, never on appear, so permission is
                // requested in direct response to the learner.
                onChange(newValue, hour, minute)
            }

            if enabled {
                DatePicker(
                    "Delivery time",
                    selection: $time,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)
                .font(AppFont.display(.subheadline, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: time) { _, newValue in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    onChange(true, parts.hour ?? hour, parts.minute ?? minute)
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .onAppear {
            enabled = isEnabled
            time = Self.date(hour: hour, minute: minute)
        }
    }

    private static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    static func title(for kind: NotificationKind) -> String {
        switch kind {
        case .dailyReminder: "Daily reminder"
        case .vocabularyReview: "Vocabulary review"
        case .listeningPractice: "Listening practice"
        case .ieltsPractice: "IELTS practice"
        case .streakReminder: "Streak reminder"
        }
    }

    static func symbol(for kind: NotificationKind) -> String {
        switch kind {
        case .dailyReminder: "sun.max.fill"
        case .vocabularyReview: "character.book.closed.fill"
        case .listeningPractice: "headphones"
        case .ieltsPractice: "globe"
        case .streakReminder: "flame.fill"
        }
    }
}

// MARK: - Practice destination

/// Where a weak topic's practise tap lands until the exercise lane ships the
/// real screen.
///
/// ponytail: a temporary shim so the weak-area list is honestly tappable today.
/// It states what it is rather than faking a quiz.
// TODO(design-system-lane): delete this and push the shared practice screen.
struct TopicPracticePlaceholder: View {

    let title: String
    let topicID: String

    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SectionHeader(title: title, subtitle: nil, actionTitle: nil, action: nil)

            EmptyStateView(
                symbol: "square.and.pencil",
                title: "Practice screen pending",
                message: "The \(title) practice set loads here once the exercise flow ships. Topic id: \(topicID).",
                actionTitle: nil,
                action: nil
            )
            .cardStyle()
        }
        .padding(Spacing.lg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Share sheet

/// A thin `UIActivityViewController` wrapper so Profile can hand over the
/// exported JSON file.
struct ShareSheet: UIViewControllerRepresentable {

    let items: [Any]
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onDone() }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
