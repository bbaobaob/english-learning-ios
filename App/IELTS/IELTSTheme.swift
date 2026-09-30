import SwiftUI

// MARK: - Palette

/// The IELTS lane's own palette: paper, ink, and the one red a marker uses.
///
/// Deliberately not the app's brand ramp — a reading passage should look like a page,
/// not like a dashboard. `Color.brand` is still used for primary actions elsewhere.
extension Color {
    /// Warm off-white page (light) / near-black slate (dark).
    static let examPaper = Color.dynamic(light: 0xFBF6EE, dark: 0x0E1014)
    /// Slightly sunk surface used for panels and the editor well.
    static let examPaperSunk = Color.dynamic(light: 0xF2E9D9, dark: 0x16191F)
    /// Body and heading ink.
    static let examInk = Color.dynamic(light: 0x16181D, dark: 0xF3EFE7)
    /// Secondary ink for captions and metadata.
    static let examInkSoft = Color.dynamic(light: 0x5C6069, dark: 0x98A0AC)
    /// Hairlines: table rules, the ruled editor, dividers.
    static let examRule = Color.dynamic(light: 0xDED3BF, dark: 0x2B3038)
    /// The single sharp accent — a marker pen.
    static let examRed = Color.dynamic(light: 0xC4441F, dark: 0xFF7043)
    /// Structural teal for "correct" and informational chips.
    static let examTeal = Color.dynamic(light: 0x16695C, dark: 0x46B8A2)
    /// Correct-answer tint.
    static let examCorrect = Color.dynamic(light: 0x1B7A4B, dark: 0x3FC48C)
    /// Wrong-answer tint.
    static let examWrong = Color.dynamic(light: 0xB3261E, dark: 0xFF7A70)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

// MARK: - Type

extension Font {
    /// Didot for titles and the question stem — a high-contrast didone reads as
    /// "printed paper" at display sizes and is deliberately unusable for body copy.
    static func examDisplay(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(weight == .bold ? "Didot-Bold" : "Didot", size: size, relativeTo: .title)
    }

    /// Didot italic, for the passage's opening line and for the exam's own voice.
    static func examDisplayItalic(_ size: CGFloat) -> Font {
        .custom("Didot-Italic", size: size, relativeTo: .title)
    }

    /// Avenir Next for everything the learner reads or types. Not Inter, not Arial.
    static func examBody(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(weightFontName(weight), size: size, relativeTo: .body)
    }

    /// Menlo for timers, word counts, and anything that must not reflow.
    static func examMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(weight == .semibold ? "Menlo-Bold" : "Menlo", size: size, relativeTo: .body)
    }

    private static func weightFontName(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold: return "AvenirNext-DemiBold"
        case .semibold: return "AvenirNext-Semibold"
        case .medium: return "AvenirNext-Medium"
        default: return "AvenirNext-Regular"
        }
    }
}

// MARK: - Metrics

enum ExamMetrics {
    /// Longest comfortable measure. Above this the eye loses the line return.
    static let readingMeasure: CGFloat = 34
    static let minReadingScale: CGFloat = 0.85
    static let maxReadingScale: CGFloat = 1.6
}

// MARK: - Surfaces

extension View {
    /// The exam page: paper surface, a hairline edge, and a soft shadow.
    func examPage(padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .background(Color.examPaper, in: .rect(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Color.examRule.opacity(0.7), lineWidth: 1)
            )
    }

    /// A caption above a value, the way a form labels a field.
    func examFieldLabel() -> some View {
        self
            .font(.examBody(11, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(Color.examInkSoft)
    }

    /// Faint horizontal rules behind an editor, like a lined exam booklet.
    func ruledPaper(interval: CGFloat = 28) -> some View {
        self.background {
            Canvas { context, size in
                var path = Path()
                var y = interval
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += interval
                }
                context.stroke(path, with: .color(Color.examRule.opacity(0.35)), lineWidth: 1)
            }
        }
    }

    /// Liquid Glass for floating controls only (toolbars pinned over content).
    /// Falls back to a material on iOS 17–25.
    ///
    /// Apply *after* layout modifiers — the glass reads the shape it is given.
    @ViewBuilder
    func examFloatingGlass(cornerRadius: CGFloat = 22) -> some View {
        if #available(iOS 26, *) {
            // TODO(design-system-lane): swap for the shared `GlassControl` wrapper once
            // the design-system lane ships one; the API here matches iOS 26 SwiftUI.
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.examRule.opacity(0.6), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Motion

enum ExamMotion {
    /// Standard reveal. Replace with the shared timing curve when it exists.
    static let reveal = Animation.spring(response: 0.5, dampingFraction: 0.86)
    /// A shorter nudge for counters and selection changes.
    static let tick = Animation.easeOut(duration: 0.18)
}

/// One place to honour Reduce Motion: every staged animation in this lane funnels through here.
extension View {
    @ViewBuilder
    func examReveal(_ isVisible: Bool, delay: Double = 0) -> some View {
        if reduceMotion {
            self.opacity(isVisible ? 1 : 0)
        } else {
            self.opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 14)
                .animation(ExamMotion.reveal.delay(delay), value: isVisible)
        }
    }
}

private struct ReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// `\.accessibilityReduceMotion` without threading an environment everywhere.
    var reduceMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }
}

extension View {
    /// Reads Reduce Motion from the environment and publishes it under our own key
    /// so `examReveal` can use it anywhere in the subtree.
    func readsReduceMotion() -> some View {
        self.environment(\.reduceMotion, self.accessibilityReduceMotion)
    }
}

// MARK: - Shared honest copy

enum ExamCopy {
    /// Shown once, plainly. The user must never think this is official test material.
    static let disclaimerTitle = "Self-authored practice, not the real test"
    static let disclaimerBody = """
        Every passage, recording script and cue card here was written for this app. \
        None of it comes from IELTS™ or its owners, and no result you get in this tab \
        is a band score. The "target band" on each lesson is the level the material is \
        pitched at, not a prediction about you.
        """

    /// The two number-like values are always labelled separately. Never "you scored band 6".
    static let accuracyLabel = "Practice accuracy"
    static let targetBandLabel = "Target band of this material"
    static let accuracyDisclaimer = "Accuracy on these questions. Not an IELTS band."
}