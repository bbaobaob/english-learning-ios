import Foundation
import UserNotifications
import EnglishStore

/// Schedules the app's five notification families.
///
/// Two rules this type exists to enforce:
///
/// * **Authorisation is requested in response to a user action, never at
///   launch.** iOS requires it, and a permission dialog on first open is the
///   fastest way to get a permanent "Don't Allow". ``requestAuthorization()``
///   is therefore called from the Profile screen's switch, never from
///   `init` or a `.task`.
/// * **Rescheduling is idempotent.** Every request removes the pending
///   requests for the five known identifiers before adding new ones, so
///   toggling a switch ten times leaves exactly five pending requests, not
///   fifty. Notification identifiers are derived from ``NotificationKind`` so
///   the removal set is complete by construction.
@MainActor
final class NotificationService {

    /// The identifier used for one kind's daily request. Derived, so a kind can
    /// never be scheduled without also being cancellable.
    private static func identifier(for kind: NotificationKind) -> String {
        "notification.\(kind.rawValue)"
    }

    /// The copy for each kind. Content lives here rather than in the resource
    /// bundle because there are five strings and no localisation yet; move them
    /// to `Localizable.xcstrings` when a second language ships.
    private static func content(for kind: NotificationKind) -> (title: String, body: String) {
        switch kind {
        case .dailyReminder:
            ("Time to study", "A few minutes today keeps your streak alive.")
        case .vocabularyReview:
            ("Words are waiting", "Your vocabulary reviews are due.")
        case .listeningPractice:
            ("Train your ear", "One short listening exercise is ready.")
        case .ieltsPractice:
            ("IELTS practice", "Keep your band score moving with one practice set.")
        case .streakReminder:
            ("Your streak is at risk", "You have not studied today yet.")
        }
    }

    /// The number of distinct identifiers the service manages, which is also the
    /// number of pending requests it will ever own.
    static var managedIdentifierCount: Int { NotificationKind.allCases.count }

    // MARK: - Authorisation

    /// The current authorisation state, read without prompting.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks for permission. Call this from a button or a switch handler, never
    /// automatically.
    ///
    /// - Returns: `true` when the learner granted permission. A refusal is not
    ///   an error to report loudly — the app works fine without notifications,
    ///   and nagging about it is worse than the missing reminder.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - Scheduling

    /// Rebuilds the whole schedule from `prefs`.
    ///
    /// Idempotent by construction: every managed identifier is removed first,
    /// then re-added for the kinds that are enabled. Calling this with the same
    /// preferences twice produces the same pending set, which is what the
    /// Profile screen's switches rely on when they call it on every change.
    ///
    /// - Parameter prefs: One preference per kind, from
    ///   `ProgressStore.notificationPrefs()`.
    func reschedule(_ prefs: [NotificationKind: NotificationPref]) {
        let center = UNUserNotificationCenter.current()
        let identifiers = NotificationKind.allCases.map(Self.identifier(for:))

        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        for kind in NotificationKind.allCases {
            guard let pref = prefs[kind], pref.enabled else { continue }
            let content = UNMutableNotificationContent()
            let copy = Self.content(for: kind)
            content.title = copy.title
            content.body = copy.body
            content.sound = .default

            var components = DateComponents()
            components.hour = min(23, max(0, pref.hour))
            components.minute = min(59, max(0, pref.minute))

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: Self.identifier(for: kind),
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    /// Removes one kind's pending request, and nothing else.
    ///
    /// This is what a switch's off-handler calls. `reschedule(_:)` cannot stand
    /// in for it: it needs the whole preference table, and rebuilding every
    /// kind's schedule to turn one off means an unrelated kind's timer is torn
    /// down and re-added on every toggle — which, for a repeating daily
    /// trigger, silently resets its time.
    ///
    /// - Parameter kind: The family to stop.
    func cancel(_ kind: NotificationKind) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.identifier(for: kind)]
        )
    }

    /// Removes every notification this service owns, and nothing else.
    func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: NotificationKind.allCases.map(Self.identifier(for:))
        )
    }
}
