import SwiftUI
import SwiftData
import EnglishCore
import EnglishStore

/// The app's entry point.
///
/// Two things are set up here and nowhere else:
///
/// * The `ModelContainer`, built from the full `EnglishStore` schema so
///   `ProgressStore.init(container:)` cannot fail its own schema check.
/// * The `AppState`, which owns the library, the audio player, and the speech
///   synthesizer for the whole process lifetime.
///
/// The container and the store are built before the first body is evaluated
/// rather than inside `body`. A `ModelContainer` created in a `View` body is
/// recreated on every invalidation, and a recreated container means an
/// in-memory-looking store that quietly loses everything.
@main
struct EnglishLearningApp: App {

    /// The persistence stack. `nil` only if the schema itself cannot be built,
    /// which is a developer error rather than a runtime condition.
    private let store: ProgressStore?
    private let startupError: String?

    init() {
        do {
            let container = try ModelContainer(
                for: UserProfile.self,
                TopicProgress.self,
                LessonProgress.self,
                AttemptRecord.self,
                ReviewState.self,
                VocabState.self,
                StudySessionRecord.self,
                StreakRecord.self,
                AchievementState.self,
                MediaBookmark.self,
                NotificationPref.self
            )
            self.store = try ProgressStore(container: container)
            self.startupError = nil
        } catch {
            // A store that cannot be built leaves the app showing an error
            // rather than trapping. A crash on launch is unrecoverable and
            // gives the learner nothing to act on; a banner at least explains
            // itself and survives a reinstall fixing the problem.
            self.store = nil
            self.startupError = Self.message(for: error)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let store {
                    RootView()
                        .environment(AppState(store: store))
                } else {
                    // No store, so no progress and no lessons. This is the one
                    // state the app cannot recover from at runtime.
                    VStack(spacing: Spacing.lg) {
                        ErrorBanner(
                            message: startupError ?? "The app's storage could not be opened.",
                            retry: nil
                        )
                        // No button here. There is nothing to retry in-process:
                        // a container that failed to build will fail again on
                        // the next attempt, and a control that pretends
                        // otherwise teaches the learner to distrust buttons.
                        Text("Restart the app to try again.")
                            .font(AppFont.body(.subheadline))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .padding(Spacing.lg)
                    .background(Palette.background)
                }
            }
            // The brand colour, applied at the root so every `tint`-taking
            // control in the app inherits it without a `.tint` on each one.
            .tint(Palette.brand)
        }
    }

    private static func message(for error: Error) -> String {
        if let storeError = error as? ProgressStore.StoreError {
            switch storeError {
            case .incompleteSchema(let missing):
                return "App storage is missing \(missing.count) data model(s). Reinstalling the app will fix it."
            }
        }
        return "App storage could not be opened: \(error.localizedDescription)"
    }
}
