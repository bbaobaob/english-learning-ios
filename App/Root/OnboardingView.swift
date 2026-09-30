import SwiftUI
import EnglishCore

/// The first-run flow: welcome, level, daily goal, and how the app works.
///
/// Four pages, one question each. Onboarding earns its length only if it
/// teaches something the learner cannot discover in ten seconds of use — so the
/// last page explains the two mechanics that are genuinely non-obvious (the
/// dictation loop and the streak), and the middle two are two taps each.
///
/// The flow is presented as a `fullScreenCover` and never appears again once
/// `onboardedAt` is set. `AppState.needsOnboarding` is the gate, and it is read
/// from the profile row rather than a user default, so clearing defaults does
/// not resurrect the flow.
struct OnboardingView: View {
    /// Called with the learner's answers. The caller writes them; this view
    /// holds no persistence.
    let onFinish: (_ name: String, _ level: Level, _ dailyMinutes: Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Int = 0
    @State private var name: String = ""
    @State private var level: Level = .beginner
    @State private var dailyMinutes: Int = 10

    /// The daily goals on offer. Five-minute steps from 5 to 45, which spans
    /// "one exercise a day" to "a full lesson a day" without becoming a
    /// commitment form.
    private let goals = [5, 10, 15, 20, 30, 45]

    private var pageCount: Int { 4 }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader

            TabView(selection: $page) {
                welcomePage.tag(0)
                levelPage.tag(1)
                goalPage.tag(2)
                explainerPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // A page swipe must not fight the vertical scroll of a page whose
            // content is taller than the screen.
            .animation(Motion.accessible(Motion.standard, reduceMotion: reduceMotion), value: page)

            footer
        }
        // The `.onboarding` backdrop: one slow wash from the top-left, leaving the
        // lower two-thirds almost entirely clear for the copy. Each page carries a
        // paragraph of text, so a backdrop that competed with it would be worse
        // than no backdrop — this one is built not to. Under Reduce Motion it is a
        // static gradient with the same composition.
        .background {
            ZStack {
                Palette.background
                AmbientBackdrop(style: .onboarding)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Chrome

    private var progressHeader: some View {
        HStack(spacing: Spacing.sm) {
            if page > 0 {
                Button {
                    Haptics.selection()
                    withAnimation(Motion.accessible(Motion.standard, reduceMotion: reduceMotion)) {
                        page -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        AppFont.body(.body, weight: .semibold)
                        .foregroundStyle(Palette.brand)
                        .frame(width: Metric.tapTarget, height: Metric.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: "Back"))
            }

            Spacer()

            HStack(spacing: Spacing.xs) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= page ? Palette.brand : Palette.field)
                        .frame(width: index == page ? 24 : 8, height: 8)
                }
            }
            .animation(Motion.accessible(Motion.quick, reduceMotion: reduceMotion), value: page)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "Page \(page + 1) of \(pageCount)"))

            Spacer()

            // A skip on the first page only. Skipping onboarding is legitimate
            // — the learner can always change the goal in Profile — but the
            // level question is worth asking, so it has no skip.
            if page == 0 {
                Button("Skip") {
                    Haptics.selection()
                    finish()
                }
                .font(AppFont.body(.subheadline, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(minHeight: Metric.tapTarget)
                .accessibilityLabel(Text(verbatim: "Skip the introduction"))
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
    }

    private var footer: some View {
        VStack(spacing: Spacing.sm) {
            PrimaryButton(
                title: page == pageCount - 1 ? "Start learning" : "Continue",
                symbol: nil,
                action: {
                    Haptics.selection()
                    if page == pageCount - 1 {
                        finish()
                    } else {
                        withAnimation(Motion.accessible(Motion.standard, reduceMotion: reduceMotion)) {
                            page += 1
                        }
                    }
                }
            )
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
    }

    private func finish() {
        onFinish(name: name, level: level, dailyMinutes: dailyMinutes)
    }

    // MARK: - Pages

    private var welcomePage: some View {
        OnboardingPage {
            VStack(spacing: Spacing.lg) {
                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Palette.brand)
                    .accessibilityHidden(true)

                Text("English Learning")
                    .font(AppFont.display(.largeTitle))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Nineteen grammar topics, vocabulary with spaced repetition, and dictation that checks every word you hear.")
                    .font(AppFont.body(.body))
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("What should we call you?", text: $name)
                    .font(AppFont.body(.body))
                    .padding(Spacing.md)
                    .frame(minHeight: Metric.buttonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                            .fill(Palette.field)
                    )
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(Text(verbatim: "Your name"))
                    .accessibilityHint(Text(verbatim: "Optional. You can leave this blank."))
            }
        }
    }

    private var levelPage: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                OnboardingHeading(
                    title: "Where are you starting?",
                    subtitle: "You can move up or down at any time. This only sets your daily goal and where the app puts you first."
                )

                VStack(spacing: Spacing.sm) {
                    ForEach(Level.allCases, id: \.self) { candidate in
                        LevelOption(
                            level: candidate,
                            isSelected: level == candidate
                        ) {
                            Haptics.selection()
                            level = candidate
                        }
                    }
                }
            }
        }
    }

    private var goalPage: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                OnboardingHeading(
                    title: "How much time a day?",
                    subtitle: "Small and daily beats long and occasional. You can change this whenever you like."
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: Spacing.md)], spacing: Spacing.md) {
                    ForEach(goals, id: \.self) { minutes in
                        GoalOption(
                            minutes: minutes,
                            isSelected: dailyMinutes == minutes
                        ) {
                            Haptics.selection()
                            dailyMinutes = minutes
                        }
                    }
                }

                Text("That is about \(AppState.dailyGoalXP(forMinutes: dailyMinutes, level: level)) XP a day at your level.")
                    .font(AppFont.body(.footnote))
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var explainerPage: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                OnboardingHeading(
                    title: "Two things worth knowing",
                    subtitle: "Everything else is discoverable by tapping. These are not."
                )

                ExplainerRow(
                    symbol: "tortoise.fill",
                    tint: Palette.brand,
                    title: "Dictation checks every word",
                    detail: "Type what you hear, hit Check, and the app marks the exact words that were wrong. Play it slowly as often as you need — the slow button is there for the words you cannot catch."
                )

                ExplainerRow(
                    symbol: "flame.fill",
                    tint: Palette.streak,
                    title: "The streak is a study streak",
                    detail: "It counts days you met your XP goal, not days you opened the app. A short session on a busy day still counts."
                )
            }
        }
    }
}

// MARK: - Page scaffolding

private struct OnboardingPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.xl)
                .padding(.bottom, Spacing.lg)
        }
        // The scroll view must not be the thing VoiceOver swipes through; the
        // page is one element with its own reading order.
        .scrollIndicators(.hidden)
    }
}

private struct OnboardingHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(AppFont.display(.title))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(AppFont.body(.subheadline))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LevelOption: View {
    let level: Level
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Palette.brand : Palette.textTertiary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(level.rawValue.capitalized)
                        .font(AppFont.display(.headline))
                        .foregroundStyle(Palette.textPrimary)
                    Text(detail(for: level))
                        .font(AppFont.body(.caption))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(isSelected ? Palette.brandSoft : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Palette.brand : Palette.separator, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(Text(verbatim: "\(level.rawValue.capitalized). \(detail(for: level))"))
    }

    private func detail(for level: Level) -> String {
        switch level {
        case .beginner: "You know the basics and want the foundations solid."
        case .intermediate: "The basics are fine; the details are what trip you up."
        case .advanced: "You want the edge cases and the exam-level precision."
        }
    }
}

private struct GoalOption: View {
    let minutes: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(minutes)")
                    .font(AppFont.display(.title3))
                    .foregroundStyle(isSelected ? Palette.surface : Palette.textPrimary)
                Text("min")
                    .font(AppFont.body(.caption2))
                    .foregroundStyle(isSelected ? Palette.surface.opacity(0.8) : Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: Metric.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(isSelected ? Palette.brand : Palette.field)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(Text(verbatim: "\(minutes) minutes a day"))
    }
}

private struct ExplainerRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: symbol)
                AppFont.body(.title3)
                .foregroundStyle(tint)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(AppFont.display(.headline))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(AppFont.body(.subheadline))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}
