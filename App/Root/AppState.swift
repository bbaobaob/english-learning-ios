import Foundation
import SwiftUI
import SwiftData
import EnglishCore
import EnglishStore

/// The app's single source of runtime state.
///
/// One instance is created at launch and injected into the environment.
/// Nothing else in the app builds a `ModelContainer`, loads a `ContentLibrary`,
/// or constructs a speech synthesizer — those are the three things that must
/// happen exactly once, and letting each screen do its own is how an app ends
/// up with two speech engines talking over each other and two divergent views
/// of the same progress row.
///
/// Views read this. They do not mutate it, except for routing, which is what
/// routing is for.
@MainActor
@Observable
final class AppState {

    // MARK: - Content

    /// The loaded course, or `nil` while loading or after a fatal load failure.
    private(set) var library: ContentLibrary?

    /// A fatal content-load failure, shown as an ``ErrorBanner`` with a retry
    /// rather than crashing. A malformed `content.json` is a deployment mistake,
    /// and the learner should still get an app that opens.
    private(set) var contentError: String?

    /// Non-fatal load diagnostics: a topic file that was skipped, an index
    /// entry with no file. Shown as a banner, and never blocking.
    private(set) var contentWarnings: [String] = []

    // MARK: - Services

    /// Persistence. Every read and write of learner progress goes through this
    /// and nowhere else.
    let store: ProgressStore

    /// The one speech synthesizer in the app.
    let speech: SpeechService

    /// The one audio player.
    let audio: AudioPlayerModel

    /// Notification scheduling. Owned here so the Profile lane does not have to
    /// build its own.
    let notifications: NotificationService

    // MARK: - Routing

    /// The selected tab. Held centrally so a deep link from one tab to another
    /// — "the topic you just got wrong is in Learn" — is one assignment rather
    /// than a notification hop.
    var selectedTab: AppTab = .home

    /// The lesson presented full-screen, by lesson id, or `nil`.
    var presentedLesson: String?

    /// One navigation path per tab, so switching tabs and coming back restores
    /// where the learner was instead of dropping them at the root.
    ///
    /// Keyed by tab and typed `[AnyHashable]` because each tab's stack holds
    /// its *own* lane's route enum — `LearnRoute` has a two-argument `.lesson`
    /// case that a shared route enum deliberately does not model, and forcing every
    /// lane onto one enum would put a `.lesson(topicID:lessonID:)` case in the
    /// vocabulary and practice tabs, which have no lessons. Each tab resolves
    /// its own routes in its own `navigationDestination`.
    private(set) var paths: [AppTab: [AnyHashable]] = [:]

    /// The navigation path of the currently selected tab.
    ///
    /// A convenience over ``paths`` so a view that only ever pushes onto the
    /// tab it is showing can bind to this directly. Settable, so
    /// `NavigationStack(path: $app.navigationPath)` works.
    var navigationPath: [AnyHashable] {
        get { paths[selectedTab] ?? [] }
        set { paths[selectedTab] = newValue }
    }

    /// Whether onboarding still needs to run, and the write that ends it.
    ///
    /// Every one of these goes through the `ProgressStore` extension the Profile
    /// lane added (`profile()`, `setProfileName`, `setDailyGoal`,
    /// `markOnboarded`) rather than through a second door onto the same row —
    /// two writers for one `UserProfile` is how the display name and the goal
    /// drift apart. This type asks the store; it never writes the row itself.

    // MARK: - Onboarding

    /// Whether the learner still has to complete onboarding.
    ///
    /// Read from the `UserProfile` row rather than a flag: `onboardedAt` is the
    /// single source of truth, so "have I onboarded" cannot disagree with
    /// "when did I onboard".
    private(set) var needsOnboarding: Bool = true

    // MARK: - Lifecycle

    init(store: ProgressStore) {
        self.store = store
        let speech = SpeechService()
        self.speech = speech
        self.audio = AudioPlayerModel(speech: speech)
        self.notifications = NotificationService()
    }

    /// Loads content and refreshes the derived state. Safe to call repeatedly;
    /// a second call re-reads the bundle.
    func bootstrap() {
        needsOnboarding = store.profile().onboardedAt == nil
        loadContent()
    }

    /// Reads the content bundle. On failure the app stays up with a banner.
    func loadContent() {
        do {
            let library = try ContentLibrary(bundle: AppState.contentBundle)
            self.library = library
            contentError = nil
            contentWarnings = library.libraryDiagnostics
        } catch {
            // A failed load leaves the previous library in place if there is
            // one, so a retry after a transient bundle problem does not blank
            // the screen the learner was looking at.
            contentError = Self.message(for: error)
        }
    }

    /// The bundle the course content lives in.
    ///
    /// `Bundle.module` is internal to `EnglishCore`, so the app cannot name it.
    /// SPM copies a resource package into the app bundle as
    /// `EnglishCore_EnglishCore.bundle`, so that is what is looked for, with the
    /// main bundle as the fallback.
    static var contentBundle: Bundle {
        if let url = Bundle.main.url(forResource: "EnglishCore_EnglishCore", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .main
    }

    private static func message(for error: Error) -> String {
        switch error {
        case let libraryError as ContentLibraryError:
            switch libraryError {
            case .missingIndex:
                return "The course index (content.json) is missing from this build."
            case .malformedIndex(let detail):
                return "The course index could not be read: \(detail)"
            case .missingContentDirectory:
                return "The course content folder is missing from this build."
            }
        default:
            return "The course content could not be loaded: \(error.localizedDescription)"
        }
    }

    // MARK: - Routing helpers

    /// The navigation path for a tab, creating it on first use.
    func path(for tab: AppTab) -> Binding<[AnyHashable]> {
        Binding(
            get: { [weak self] in self?.paths[tab] ?? [] },
            set: { [weak self] newValue in self?.paths[tab] = newValue }
        )
    }

    /// Pushes a route onto a tab's stack.
    func navigate(_ route: AnyHashable, in tab: AppTab) {
        selectedTab = tab
        paths[tab, default: []].append(route)
    }

    /// Clears a tab's stack, e.g. after a lesson completes.
    func resetPath(for tab: AppTab) {
        paths[tab] = []
    }

    // MARK: - Onboarding

    /// Writes the learner's onboarding answers and stops showing the flow.
    ///
    /// All three fields go through the store's own setters, so the Profile lane
    /// stays the only thing that writes a `UserProfile` — `AppState` asks, it
    /// does not reach in.
    ///
    /// - Parameters:
    ///   - name: The display name. Ignored when blank, so the Profile screen
    ///     keeps its "Learner" default rather than showing an empty header.
    ///   - level: The starting difficulty, used to price the daily goal.
    ///   - dailyMinutes: The learner's chosen daily study time.
    func completeOnboarding(name: String, level: Level, dailyMinutes: Int) {
        store.setProfileName(name)
        store.setDailyGoal(AppState.dailyGoalXP(forMinutes: dailyMinutes, level: level))
        store.markOnboarded()
        needsOnboarding = false
    }

    /// The XP a day of `minutes` study is worth, by starting level.
    ///
    /// 10 XP per minute at beginner, rising with level: a more experienced
    /// learner clears a lesson faster, so a flat rate would make the goal
    /// trivial for them and unreachable for a beginner.
    ///
    /// ponytail: a flat per-minute rate, not a measured difficulty model. If
    /// goal-completion rates turn out to differ sharply between levels, give
    /// this a table driven by real completion data.
    static func dailyGoalXP(forMinutes minutes: Int, level: Level) -> Int {
        let perMinute: Int
        switch level {
        case .beginner: perMinute = 10
        case .intermediate: perMinute = 12
        case .advanced: perMinute = 15
        }
        // `setDailyGoal` clamps to 10...500, so no clamp is needed here.
        return max(10, minutes * perMinute)
    }
}

/// The six top-level destinations, in the order they appear in the tab bar.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case learn
    case practice
    case ielts
    case vocabulary
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .learn: "Learn"
        case .practice: "Practice"
        case .ielts: "IELTS"
        case .vocabulary: "Vocabulary"
        case .profile: "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .learn: "book.fill"
        case .practice: "dumbbell.fill"
        case .ielts: "graduationcap.fill"
        case .vocabulary: "text.book.closed.fill"
        case .profile: "person.crop.circle.fill"
        }
    }

    /// Whether this tab's lane brings its own `NavigationStack`.
    ///
    /// `LearnHomeView` and `IELTSHomeView` wrap themselves in one bound to
    /// `app.navigationPath`; `VocabularyHomeView` wraps one bound to its own
    /// `@State` path, which also means its scroll position is per-view and
    /// would be lost on a tab switch if the tab bar owned the stack. Adding a
    /// second stack around any of them produces a back-swipe that pops the
    /// inner one while the tab bar stays put. See ``TabRootScreen``.
    var laneSuppliesItsOwnStack: Bool {
        switch self {
        case .learn, .ielts, .vocabulary: true
        case .home, .practice, .profile: false
        }
    }
}
