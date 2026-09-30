import SwiftUI
import EnglishCore

/// The app's top-level view: onboarding, or the tab shell.
///
/// The split is deliberate. Onboarding is a `fullScreenCover` over the tab
/// shell rather than a branch in it, so the tab bar is already built when
/// onboarding finishes and the learner lands on a populated Home instead of a
/// screen that has to build itself in front of them.
struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app

        RootTabView()
            .fullScreenCover(isPresented: onboardingBinding) {
                OnboardingView { name, level, dailyMinutes in
                    app.completeOnboarding(name: name, level: level, dailyMinutes: dailyMinutes)
                }
                .environment(app)
            }
            .task {
                app.bootstrap()
            }
    }

    /// Onboarding's visibility, derived rather than stored.
    ///
    /// The setter never clears the flag. A `fullScreenCover` must not be
    /// dismissible by a swipe, because a half-finished onboarding would leave
    /// a profile with no `onboardedAt` and the flow would return on the next
    /// launch anyway — the learner would be stuck in a loop they cannot
    /// escape. Destructive writes belong in ``completeOnboarding(_:level:dailyMinutes:)``,
    /// which onboarding's own button calls.
    private var onboardingBinding: Binding<Bool> {
        Binding(get: { app.needsOnboarding }, set: { _ in })
    }
}

/// The six-tab shell.
///
/// Each tab owns a `NavigationStack` with its own path, stored in
/// `AppState.paths`. That is the reason for a per-tab path rather than one
/// shared stack: switching tabs and switching back must return the learner to
/// the screen they left, which is what `NavigationStack(path:)` bound to a
/// dictionary value gives and what a single shared stack cannot.
struct RootTabView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app

        TabView(selection: $app.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Group {
                    if tab.laneSuppliesItsOwnStack {
                        // The lane brought a stack; do not add a second one.
                        TabRootScreen(tab: tab)
                    } else {
                        // The path is `[AnyHashable]` so each tab's stack can
                        // carry its own lane's route enum: `LearnRoute.lesson`
                        // takes two arguments and `.alphabet` has no equivalent
                        // in any other tab, so one shared route enum would be
                        // wrong for five tabs. Each lane's root view registers
                        // its own `navigationDestination(for:)`, and SwiftUI
                        // resolves the most specific registered type — so two
                        // lanes can both have a `case topic(String)`.
                        NavigationStack(path: app.path(for: tab)) {
                            TabRootScreen(tab: tab)
                        }
                    }
                }
                .tabItem {
                    Label(tab.title, systemImage: tab.symbol)
                }
                .tag(tab)
            }
        }
        .tint(Palette.brand)
        .modifier(TabBarGlass())
    }
}

/// The tab bar treatment.
///
/// On iOS 26 the system tab bar is already Liquid Glass and needs nothing from
/// us beyond the brand tint. Before that, the bar is a flat material by
/// default and the lesson screens underneath are content-coloured, so the
/// toolbar background is made explicit — otherwise the bar reads as a
/// different colour from the page it sits on.
private struct TabBarGlass: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else {
            content.toolbarBackground(.visible, for: .tabBar)
        }
    }
}

/// The root screen of one tab.
///
/// A dispatch point, not a stub: each case names the view its owning lane
/// ships. A lane's root view reads `AppState`, `ProgressStore`,
/// `AudioPlayerModel`, and `SpeechService` from the environment, so this file
/// never has to be edited again when a lane adds a screen.
///
/// **Three lanes bring their own `NavigationStack`.** `LearnHomeView` and
/// `IELTSHomeView` wrap themselves in one bound to `app.navigationPath`;
/// `VocabularyHomeView` wraps one bound to its own `@State` path. All three were
/// written before this shell existed. Nesting a `NavigationStack` inside another
/// produces a back-swipe that pops the inner stack while the tab bar stays put —
/// a genuinely confusing gesture, not a cosmetic one. Rather than edit three
/// lanes' files, the tab bar's own stack is dropped for exactly those tabs, so
/// each tab has one stack and the learner's position is preserved by whichever
/// one owns it.
///
/// // TODO(learn, ielts, vocabulary): move all three onto
/// `app.path(for: .learn)` / `.ielts` / `.vocabulary`, then delete
/// `AppTab.laneSuppliesItsOwnStack` and the branch in `RootTabView`.
struct TabRootScreen: View {
    let tab: AppTab
    @Environment(AppState.self) private var app

    /// Whether the lane's root view brings its own `NavigationStack`.
    private var laneSuppliesItsOwnStack: Bool {
        tab.laneSuppliesItsOwnStack
    }

    var body: some View {
        Group {
            switch tab {
            case .home: HomeView()
            case .learn: LearnHomeView()
            case .practice: PracticeHomeView()
            case .ielts: IELTSHomeView()
            case .vocabulary: VocabularyHomeView()
            case .profile: ProfileView()
            }
        }
        .background(Palette.background)
    }
}
