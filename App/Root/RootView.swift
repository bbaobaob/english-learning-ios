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
                NavigationStack(path: app.path(for: tab)) {
                    TabRootScreen(tab: tab)
                        .navigationDestination(for: AppRoute.self) { route in
                            RouteDestination(route: route)
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
/// This is a dispatch point, not a stub. Each case is one line naming the view
/// its owning lane ships; until that lane lands, the tab shows a labelled
/// placeholder that says which lane owes it, rather than an empty white screen
/// that looks like a bug in this lane's code.
///
/// // TODO(lanes): replace the `EmptyStateView` in each case with the owning
/// lane's root view, e.g. `HomeView(store: app.store, library: app.library)`.
/// The signature to code against is `AppTab` and the environment already
/// carries `AppState`, `ProgressStore`, `AudioPlayerModel`, and `SpeechService`.
struct TabRootScreen: View {
    let tab: AppTab
    @Environment(AppState.self) private var app

    var body: some View {
        Group {
            switch tab {
            case .home:
                // TODO(home)
                placeholder(for: tab)
            case .learn:
                // TODO(learn)
                placeholder(for: tab)
            case .practice:
                // TODO(practice)
                placeholder(for: tab)
            case .ielts:
                // TODO(ielts)
                placeholder(for: tab)
            case .vocabulary:
                // TODO(vocabulary)
                placeholder(for: tab)
            case .profile:
                // TODO(profile)
                placeholder(for: tab)
            }
        }
        .background(Palette.background)
    }

    private func placeholder(for tab: AppTab) -> some View {
        EmptyStateView(
            symbol: tab.symbol,
            title: tab.title,
            message: app.contentError
                ?? (app.library == nil
                    ? "Loading the course…"
                    : "This section is on its way.")
        )
    }
}

/// Resolves a pushed route to its screen.
///
/// Same contract as ``TabRootScreen``: one line per case for the owning lane.
/// The routing, the paths, and the tab association are already done, so a lane
/// only has to supply the view for its own destinations.
struct RouteDestination: View {
    let route: AppRoute
    @Environment(AppState.self) private var app

    var body: some View {
        Group {
            switch route {
            case .topic(let topicID):
                // TODO(learn): TopicDetailView(topicID:)
                unavailable(title: topicID)
            case .lesson(let lessonID):
                // TODO(learn): LessonFlowView(lessonID:)
                unavailable(title: lessonID)
            case .vocabulary:
                // TODO(vocabulary): VocabularyDeckView()
                unavailable(title: "Vocabulary")
            case .ielts(let moduleID):
                // TODO(ielts): IELTSModuleView(moduleID:)
                unavailable(title: moduleID)
            case .practice(let setID):
                // TODO(practice): PracticeSetView(setID:)
                unavailable(title: setID)
            }
        }
        .background(Palette.background)
    }

    /// Resolves an id to a human title where the library can, so the
    /// navigation bar is not empty.
    private func unavailable(title: String) -> some View {
        EmptyStateView(
            symbol: "square.stack.3d.up.slash",
            title: resolvedTitle(fallback: title),
            message: "This screen is on its way."
        )
    }

    private func resolvedTitle(fallback: String) -> String {
        guard let library = app.library else { return fallback }
        return library.topic(fallback)?.title
            ?? library.lesson(fallback)?.title
            ?? library.ieltsLesson(fallback)?.title
            ?? fallback
    }
}
