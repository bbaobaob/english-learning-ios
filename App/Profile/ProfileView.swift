import SwiftUI
import EnglishCore
import EnglishStore

/// The learner profile, progress history, settings and data controls.
///
/// One screen, one `ScrollView`, one model. Every number comes from
/// `ProfileModel`, which reads `ProgressStore` and `ContentLibrary`; the view
/// only lays it out.
struct ProfileView: View {

    @Environment(AppState.self) private var app
    @State private var model = ProfileModel()

    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("reduceMotionAcknowledged") private var reduceMotionAcknowledged = false

    @State private var isEditingName = false
    @State private var nameDraft = ""
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var isConfirmingReset = false
    @State private var notificationError: String?
    @State private var prefs: [NotificationKind: NotificationPref] = [:]
    @State private var notifications = NotificationService()
    @State private var goalFocus = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    header

                    if let notificationError {
                        ErrorBanner(message: notificationError) { notificationError = nil }
                    }

                    streakSection
                    goalSection
                        .id(Self.goalAnchor)
                    skillSection
                    weakAreaSection
                    achievementSection
                    settingsSection
                    notificationSection
                    dataSection
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .background(background)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .task { reload() }
            .refreshable { reload() }
            .onChange(of: goalFocus) { _, focused in
                guard focused else { return }
                withAnimation { proxy.scrollTo(Self.goalAnchor, anchor: .top) }
                goalFocus = false
            }
            .onChange(of: model.weakSort) { _, _ in model.resortWeakAreas() }
            .preferredColorScheme(preferredScheme)
            .alert("Reset all progress?", isPresented: $isConfirmingReset) {
                Button("Reset", role: .destructive) {
                    model.reset(store: app.store, library: app.library)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Streaks, XP, achievements and every saved attempt are deleted. This cannot be undone.")
            }
            .sheet(isPresented: $isExporting) {
                if let exportURL {
                    ShareSheet(items: [exportURL]) {
                        self.exportURL = nil
                        isExporting = false
                    }
                }
            }
        }
    }

    /// Scroll target for the "Goal N XP" shortcut in the header.
    private static let goalAnchor = "daily-goal"

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(nameLine)
                        .font(AppFont.display(.title2, weight: .bold))
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Learner name, \(nameLine)")

                    HStack(spacing: Spacing.xs) {
                        LevelPill(text: "Level \(model.learnerLevel)")
                        Text("Joined \(model.joinedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(AppFont.display(.footnote, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: Spacing.sm)

                XPBadge(xp: model.totalXP)
            }

            HStack(spacing: Spacing.sm) {
                SecondaryButton(title: "Edit name", symbol: "pencil") {
                    nameDraft = model.name
                    isEditingName = true
                }
                .accessibilityHint("Opens a text field to change your display name")

                SecondaryButton(title: "Goal \(model.dailyGoalXP) XP", symbol: "target") {
                    goalFocus = true
                }
                .accessibilityHint("Scrolls to the daily goal setting")
            }
        }
        .padding(Spacing.lg)
        .cardStyle()
        .alert("Your name", isPresented: $isEditingName) {
            TextField("Name", text: $nameDraft)
            Button("Save") { model.updateName(nameDraft, store: app.store) }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Lifetime study time, formatted once so every card reads the same way.
    private var studyTimeText: String {
        let minutes = model.studyMinutes
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m"
    }

    private var nameLine: String {
        let trimmed = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Learner" : trimmed
    }

    // MARK: - Streak

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            GlassSectionHeader(title: "Streak", subtitle: model.totalDays == 0 ? "No study days yet" : "\(model.totalDays) study days")

            HStack(spacing: Spacing.md) {
                StatCard(title: "Current", value: "\(model.currentStreak)", caption: "days", symbol: "flame.fill", tint: .streak)
                StatCard(title: "Longest", value: "\(model.longestStreak)", caption: "days", symbol: "crown.fill", tint: .xp)
                StatCard(title: "Total", value: "\(model.totalDays)", caption: "days", symbol: "calendar", tint: .brand)
            }

            ForEach(model.heatMaps) { map in
                StudyHeatMap(month: map)
            }
        }
    }

    // MARK: - Daily goal

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            GlassSectionHeader(title: "Daily goal", subtitle: "XP per day to keep the streak")

            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text("Target")
                        .font(AppFont.display(.subheadline, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(model.dailyGoalXP) XP")
                        .font(AppFont.mono(.headline, weight: .semibold))
                        .foregroundStyle(Color.brand)
                        .contentTransition(.numericText())
                        .accessibilityLabel("Daily goal \(model.dailyGoalXP) experience points")
                }

                Stepper(
                    value: Binding(
                        get: { model.dailyGoalXP },
                        set: { newValue in
                            model.updateDailyGoal(newValue, store: app.store, library: app.library)
                        }
                    ),
                    in: 10...500,
                    step: 10
                ) {
                    Text("Adjust in steps of 10 XP")
                        .font(AppFont.display(.footnote, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Text("This also drives the streak count: a day counts once its XP reaches this target.")
                    .font(AppFont.display(.caption, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .padding(Spacing.lg)
            .cardStyle()
        }
    }

    // MARK: - Skills

    private var skillSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            GlassSectionHeader(title: "Progress by skill", subtitle: "Accuracy on grammar topics, study time elsewhere")

            VStack(spacing: 0) {
                ForEach(Array(model.skills.enumerated()), id: \.element.id) { index, skill in
                    SkillProgressRow(skill: skill)
                    if index < model.skills.count - 1 {
                        Divider().padding(.leading, Spacing.xl + 44)
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
            .cardStyle()

            HStack(spacing: Spacing.sm) {
                StatCard(
                    title: "Study time",
                    value: studyTimeText,
                    caption: "total",
                    symbol: "clock.fill",
                    tint: .brand
                )
                StatCard(
                    title: "Accuracy",
                    value: "\(Int((model.accuracy * 100).rounded()))%",
                    caption: "lifetime",
                    symbol: "scope",
                    tint: .accuracy
                )
                StatCard(
                    title: "Lessons",
                    value: "\(model.lessonsCompleted)",
                    caption: "finished",
                    symbol: "book.fill",
                    tint: .success
                )
            }

            Text("\(model.wordsMastered) words mastered · \(model.reviewsDone) reviews done · \(model.ieltsCompleted) IELTS modules started")
                .font(AppFont.display(.footnote, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xs)

            if model.last14Days.contains(where: { $0.minutes > 0 }) {
                Last14DaysChart(days: model.last14Days)
            } else {
                EmptyStateView(
                    symbol: "chart.bar",
                    title: "No study history yet",
                    message: "Finish a lesson or a review and this chart fills in with your last fourteen days.",
                    actionTitle: nil,
                    action: nil
                )
                .padding(.vertical, Spacing.sm)
                .cardStyle()
            }
        }
    }

    // MARK: - Weak areas

    private var weakAreaSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            GlassSectionHeader(title: "Weak areas", subtitle: model.weakAreas.isEmpty ? "Nothing to rank yet" : "Sorted by \(model.weakSort.rawValue.lowercased())")

            if model.weakAreas.isEmpty {
                EmptyStateView(
                    symbol: "target",
                    title: "No attempts yet",
                    message: "Answer a few exercises and your weakest topics appear here, ranked so you know where to practise.",
                    actionTitle: nil,
                    action: nil
                )
                .cardStyle()
            } else {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Picker(
                        "Sort weak areas",
                        selection: Binding(
                            get: { model.weakSort },
                            set: { model.weakSort = $0 }
                        )
                    ) {
                        ForEach(ProfileModel.WeakSort.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    ForEach(model.weakAreas) { area in
                        NavigationLink {
                            // TODO(design-system-lane): replace with the shared topic practice screen once App/Exercise ships it.
                            TopicPracticePlaceholder(title: area.title, topicID: area.id)
                        } label: {
                            WeakAreaRow(area: area)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.md)
                .cardStyle()
            }
        }
    }

    // MARK: - Achievements

    private var achievementSection: some View {
        let unlocked = model.achievements.filter(\.isUnlocked).count
        return VStack(alignment: .leading, spacing: Spacing.md) {
            GlassSectionHeader(title: "Achievements", subtitle: "\(unlocked) of \(model.achievements.count) earned")

            if model.achievements.isEmpty {
                EmptyStateView(symbol: "trophy", title: "No badges loaded", message: "Achievements appear as soon as the catalogue is available.", actionTitle: nil, action: nil)
                    .cardStyle()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.md)], spacing: Spacing.md) {
                    ForEach(model.achievements) { badge in
                        AchievementTile(badge: badge)
                    }
                }
            }
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            GlassSectionHeader(title: "Settings", subtitle: nil)

            VStack(spacing: 0) {
                settingsRow(
                    title: "Appearance",
                    symbol: "circle.lefthalf.filled",
                    tint: .brand
                ) {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Appearance, \(Appearance(rawValue: appearance)?.title ?? "System")")
                }

                Divider().padding(.leading, Spacing.xl + 44)

                settingsRow(title: "Haptics", symbol: "hand.tap.fill", tint: .xp) {
                    Toggle("Haptics", isOn: $hapticsEnabled)
                        .labelsHidden()
                        .onChange(of: hapticsEnabled) { _, on in
                            if on { Haptics.selection() }
                        }
                        .accessibilityLabel("Haptics")
                }

                Divider().padding(.leading, Spacing.xl + 44)

                settingsRow(title: "Reduce motion", symbol: "figure.walk.motion", tint: .warning) {
                    Toggle("Reduce motion", isOn: $reduceMotionAcknowledged)
                        .labelsHidden()
                        .accessibilityLabel("Reduce motion")
                        .accessibilityHint("Acknowledged so the app can keep large transitions minimal")
                }
            }
            .padding(.vertical, Spacing.xs)
            .cardStyle()

            if reduceMotionAcknowledged {
                Text("Transitions are kept short on every screen. The system Reduce Motion setting still wins where it applies.")
                    .font(AppFont.display(.caption, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.xs)
            }
        }
    }

    private func settingsRow<Accessory: View>(
        title: String,
        symbol: String,
        tint: Color,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28)
                .accessibilityHidden(true)

            Text(title)
                .font(AppFont.display(.body, weight: .medium))
                .foregroundStyle(.primary)

            Spacer(minLength: Spacing.sm)

            accessory()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    // MARK: - Notifications

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            GlassSectionHeader(title: "Notifications", subtitle: "Nothing is scheduled until you switch one on")

            VStack(spacing: 0) {
                ForEach(Array(NotificationKind.allCases.enumerated()), id: \.element) { index, kind in
                    NotificationRow(
                        kind: kind,
                        isEnabled: prefs[kind]?.enabled ?? false,
                        hour: prefs[kind]?.hour ?? 9,
                        minute: prefs[kind]?.minute ?? 0
                    ) { enabled, hour, minute in
                        apply(kind: kind, enabled: enabled, hour: hour, minute: minute)
                    }
                    if index < NotificationKind.allCases.count - 1 {
                        Divider().padding(.leading, Spacing.lg)
                    }
                }
            }
            .cardStyle()

            if let notificationError {
                Text(notificationError)
                    .font(AppFont.display(.caption, weight: .regular))
                    .foregroundStyle(Color.danger)
            }
        }
    }

    /// Writes one preference and reschedules it.
    ///
    /// Authorization is requested here, in the tap handler, and nowhere else:
    /// a screen may never ask for notification permission on appear.
    private func apply(kind: NotificationKind, enabled: Bool, hour: Int, minute: Int) {
        app.store.setNotificationPref(kind, enabled: enabled, hour: hour, minute: minute)
        reloadPrefs()

        guard enabled else {
            // Only `cancelAll()` is in the frozen contract, so dropping the last
            // enabled kind is the only safe call: with others still on, the
            // schedule is left alone and the next reschedule of those kinds
            // keeps them alive.
            let stillEnabled = prefs.values.contains { $0.enabled }
            if !stillEnabled { notifications.cancelAll() }
            return
        }

        Task {
            do {
                let granted = try await notifications.requestAuthorization()
                guard granted else {
                    notificationError = "Notifications are turned off for this app in iOS Settings."
                    return
                }
                // TODO(design-system-lane): `reschedule(_:)` is assumed to take the kind and
                // re-read the preference from the store, making it idempotent.
                notifications.reschedule(kind)
                notificationError = nil
            } catch {
                notificationError = error.localizedDescription
            }
        }
    }

    private func reloadPrefs() {
        prefs = app.store.notificationPrefs()
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            GlassSectionHeader(title: "Data", subtitle: nil)

            VStack(spacing: Spacing.md) {
                PrimaryButton(title: "Export progress", symbol: "square.and.arrow.up") {
                    export()
                }

                SecondaryButton(title: "Reset all progress", symbol: "trash") {
                    isConfirmingReset = true
                }

                if let message = model.dataMessage {
                    Text(message)
                        .font(AppFont.display(.footnote, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(Spacing.lg)
            .cardStyle()
        }
    }

    private func export() {
        do {
            let data = try ProgressExporter.json(store: app.store, library: app.library)
            let name = "english-progress-\(Date().formatted(.iso8601.year().month().day())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            exportURL = url
            isExporting = true
            model.dataMessage = "Exported \(name)."
        } catch {
            model.dataMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Chrome

    private var background: some View {
        LinearGradient(
            colors: [Color.brandSoft.opacity(0.5), Color.clear],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }

    /// The colour scheme this screen renders in.
    ///
    /// `nil` means "follow the system", which is what a `preferredColorScheme`
    /// of `nil` means too — so the picker needs no special case.
    // TODO(design-system-lane): the Root lane should apply this to the whole
    // window; until it does, this override is scoped to the Profile screen.
    private var preferredScheme: ColorScheme? {
        switch Appearance(rawValue: appearance) {
        case .light: .light
        case .dark: .dark
        default: nil
        }
    }

    private func reload() {
        model.load(store: app.store, library: app.library)
        reloadPrefs()
    }
}

// MARK: - Appearance

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var id: String { rawValue }
}
