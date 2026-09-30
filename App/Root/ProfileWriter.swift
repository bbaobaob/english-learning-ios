import Foundation
import SwiftData
import EnglishCore
import EnglishStore

/// The bridge to the one `UserProfile` row.
///
/// `ProgressStore`'s frozen API has no profile read or write — the architecture
/// lists `UserProfile` in the schema but no accessor for it. Onboarding is the
/// only screen that needs it, so this is a deliberately small, local bridge
/// rather than a change to a package another lane owns.
///
/// It is a class, not a view, so the "no `ModelContext` in views" rule holds:
/// `OnboardingView` calls two methods and never sees a context.
///
/// // TODO(store): fold `needsOnboarding()` and `saveProfile(name:level:dailyMinutes:)`
/// into `ProgressStore` and delete this file. They belong beside
/// `setNotificationPref`, not in the app target.
@MainActor
final class ProfileWriter {

    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    /// The single profile row, or `nil` before onboarding has created it.
    func profile() -> UserProfile? {
        let descriptor = FetchDescriptor<UserProfile>()
        return (try? container.mainContext.fetch(descriptor))?.first
    }

    /// Whether onboarding still needs to run.
    func needsOnboarding() -> Bool {
        guard let profile = profile() else { return true }
        return profile.onboardedAt == nil
    }

    /// Creates or updates the profile and stamps `onboardedAt`.
    ///
    /// The `name` is trimmed and falls back to a default, because a blank
    /// name would render as an empty header on Home forever.
    ///
    /// - Parameters:
    ///   - name: The learner's display name.
    ///   - level: The starting difficulty. Stored as the daily-goal
    ///     multiplier, because `UserProfile` has no level column — see
    ///     `xpPerMinute(for:)` for why.
    ///   - dailyMinutes: The learner's chosen daily study time.
    func saveProfile(name: String, level: Level, dailyMinutes: Int) {
        let context = container.mainContext
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let row = profile() ?? {
            let created = UserProfile(name: trimmed, createdAt: Date())
            context.insert(created)
            return created
        }()

        row.name = trimmed.isEmpty ? "Learner" : trimmed
        // 10 XP per minute at beginner, more at higher levels: a more
        // experienced learner clears a lesson faster, so a flat rate would
        // make the goal trivial for them and impossible for a beginner.
        // ponytail: an XP-per-minute estimate, not a measured difficulty
        // model. Add a real one if goal completion rates turn out to differ
        // sharply between levels.
        row.dailyGoalXP = max(10, dailyMinutes * Self.xpPerMinute(for: level))
        row.onboardedAt = Date()
        try? context.save()

        // The streak row caches the goal for the Home ring, so it has to be
        // brought along or the two disagree for the rest of the install.
        syncStreakGoal(to: row.dailyGoalXP)
    }

    /// The XP a minute of study is worth, by starting level.
    static func xpPerMinute(for level: Level) -> Int {
        switch level {
        case .beginner: 10
        case .intermediate: 12
        case .advanced: 15
        }
    }

    private func syncStreakGoal(to goal: Int) {
        let context = container.mainContext
        let descriptor = FetchDescriptor<StreakRecord>()
        guard let streak = (try? context.fetch(descriptor))?.first else { return }
        streak.xpGoal = goal
        try? context.save()
    }
}
