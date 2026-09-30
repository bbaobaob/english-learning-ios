import SwiftUI

// MARK: - Spacing
//
// One scale, used everywhere. 4pt base so every value is a multiple of the
// 4pt grid iOS itself snaps to at 1x/2x/3x. Nothing here is a magic number:
// if a gap looks wrong, change the scale, not the call site.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

// MARK: - Radius
//
// `.card` is the one radius the app reads as "this is a discrete surface".
// `.chip` is for interactive pills that are smaller than a card. `.pill` is for
// anything fully round — badges, dots, the flame.
enum Radius {
    static let card: CGFloat = 16
    static let chip: CGFloat = 10
    static let pill: CGFloat = 999
}

// MARK: - Palette
//
// Every colour is an adaptive pair. Light and dark are *designed* against each
// other, not derived by inverting: dark surfaces are lifted off pure black
// (so elevation reads) and saturated accents are lightened so they keep their
// contrast on a dark ground. No hex is ever used directly by a view — a view
// asks for a role (`Palette.surface`, `Color.danger`), and this file decides
// what that role looks like in each scheme.
enum Palette {
    // Neutral scaffolding.
    /// The page ground behind every scroll view.
    static let background = Color.adaptive(light: 0xF7F6F2, dark: 0x0B0C10)
    /// A resting card: a card on the page.
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x16181F)
    /// A card on a card, or a card that should float above its sibling.
    static let surfaceRaised = Color.adaptive(light: 0xFFFCF7, dark: 0x1E212A)
    /// A pressed / selected well, e.g. a text field or a selected option.
    static let field = Color.adaptive(light: 0xF1EFE8, dark: 0x22262F)

    // Text.
    static let textPrimary = Color.adaptive(light: 0x14161C, dark: 0xF2F3F7)
    static let textSecondary = Color.adaptive(light: 0x5A5F6E, dark: 0xA7ADBE)
    static let textTertiary = Color.adaptive(light: 0x8A8F9E, dark: 0x767C8C)
    /// Hairlines. Never used for text — text contrast must not rely on a line.
    static let separator = Color.adaptive(light: 0xE3E1DA, dark: 0x2A2E39)

    // Brand and meaning. The accents are the only saturated colours in the
    // app; content surfaces stay neutral so an accent always means something.
    static let brand = Color.adaptive(light: 0x3B37D6, dark: 0x8B87FF)
    /// A wash of the brand for selected chips and tinted callouts.
    static let brandSoft = Color.adaptive(light: 0xE6E4FF, dark: 0x241F52)
    static let success = Color.adaptive(light: 0x0E8A5F, dark: 0x3DD68C)
    static let warning = Color.adaptive(light: 0xB06A00, dark: 0xFFB340)
    static let danger = Color.adaptive(light: 0xC42B1C, dark: 0xFF7A70)
    static let streak = Color.adaptive(light: 0xFF6B2C, dark: 0xFF9A5C)
    static let xp = Color.adaptive(light: 0x7A3EF2, dark: 0xB48BFF)
    static let accuracy = Color.adaptive(light: 0x0A6FB8, dark: 0x62B4F0)

    // Tinted feedback surfaces. Paired with the accents above so a correct
    // answer is a coloured *panel*, not just coloured text — colour alone is
    // not an accessible signal, and the `symbol` on the result row is what
    // actually carries the meaning.
    static let successSurface = Color.adaptive(light: 0xE4F6EE, dark: 0x10301F)
    static let dangerSurface = Color.adaptive(light: 0xFCEBE9, dark: 0x3A1512)
    static let warningSurface = Color.adaptive(light: 0xFDF1DF, dark: 0x33240A)

    // Shadows are only used in dark mode; in light mode the border does the
    // separating. A shadow on a light surface reads as dirt.
    static let shadow = Color.adaptive(light: 0x00000000, dark: 0x00000059)
}

// MARK: - Semantic colour shortcuts
//
// Views use these. `Palette` exists for the pairs a view wants to coordinate
// (an accent and its matching wash); `Color.*` exists for the single-role case,
// which is the common one.
extension Color {
    static let brand = Palette.brand
    static let brandSoft = Palette.brandSoft
    static let success = Palette.success
    static let warning = Palette.warning
    static let danger = Palette.danger
    static let streak = Palette.streak
    static let xp = Palette.xp
    static let accuracy = Palette.accuracy

    static let background = Palette.background
    static let surface = Palette.surface
    static let surfaceRaised = Palette.surfaceRaised
    static let field = Palette.field
    static let textPrimary = Palette.textPrimary
    static let textSecondary = Palette.textSecondary
    static let textTertiary = Palette.textTertiary
    static let separator = Palette.separator
}

// MARK: - Adaptive colour construction

extension Color {
    /// A colour that resolves per trait collection.
    ///
    /// This is the only way a colour is defined in the app. A hard-coded hex
    /// cannot respond to Dark Mode, to Increase Contrast, or to a future
    /// tinted-device scheme, and one of those three always breaks first.
    ///
    /// - Parameters:
    ///   - light: 24-bit RGB for the light scheme.
    ///   - dark: 24-bit RGB for the dark scheme.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark)
                : UIColor(rgb: light)
        })
    }
}

extension UIColor {
    /// Builds a colour from a `0xRRGGBB` literal.
    fileprivate convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Type
//
// Two families, chosen so they cannot be confused with each other:
//   * `display` — a serif (New York) for titles, numbers, and anything that
//     anchors a screen. It gives the app an editorial, book-like voice that a
//     system-default app never has.
//   * everything else — the system face, which is the most legible face on the
//     platform and already respects the user's text size.
//   * `mono` — monospaced digits, for times, scores, and counters, so digits
//     do not jitter as they tick.
//
// Both helpers take a `Font.TextStyle` and never a point size, so every glyph
// in the app scales with the user's Dynamic Type setting. `Font.TextStyle`
// resolves against `UIFontMetrics` internally, so this is real Dynamic Type
// scaling and not `Font.custom` with a hard-coded size pretending to be.
enum AppFont {
    /// The display face: a serif, Dynamic Type aware.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        Font.system(style, design: .serif).weight(weight)
    }

    /// The body face: the system face, Dynamic Type aware.
    static func body(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        Font.system(style, design: .default).weight(weight)
    }

    /// Tabular figures, for elapsed/total time, XP, and step counters.
    static func mono(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        Font.system(style, design: .monospacedDigit).weight(weight)
    }
}

// MARK: - Motion
//
// A single vocabulary of durations, so a screen that wants "a bit of life"
// reaches for one of these rather than inventing `0.23`.
enum Motion {
    /// State flips: selection, chip toggles, ring fills.
    static let quick = Animation.easeOut(duration: 0.18)
    /// Elements arriving: banners, result panels, sheets.
    static let standard = Animation.spring(response: 0.36, dampingFraction: 0.82)
    /// Deliberate, attention-drawing motion: a correct answer landing.
    static let emphatic = Animation.spring(response: 0.5, dampingFraction: 0.7)

    /// `nil` under Reduce Motion, so a caller can write
    /// `.animation(Motion.accessible(Motion.quick, reduceMotion: reduceMotion))`
    /// and get the right behaviour without an `if` at the call site.
    ///
    /// This is a gate, not a substitution: under Reduce Motion the *value* is
    /// discarded but the view still updates, so nothing that was previously
    /// shown on screen becomes invisible. Effects that remove travel or repeat
    /// are handled inside their own modifiers instead.
    static func accessible(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

extension Animation {
    /// The same gate as ``Motion/accessible(_:reduceMotion:)``, for a call site
    /// that already has a bare `Animation` in hand.
    static func accessible(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        Motion.accessible(animation, reduceMotion: reduceMotion)
    }
}

// MARK: - Sizing
//
// The few fixed dimensions the app uses. These are *not* text sizes: a button
// has a minimum height so it can be tapped, and the value grows with Dynamic
// Type rather than clipping, which is what `View.minimumScaleFactor`-style
// workarounds get wrong.
enum Metric {
    /// Apple's minimum comfortable tap target. Every tappable row is at least
    /// this tall, whatever its Dynamic Type size.
    static let tapTarget: CGFloat = 44
    /// Default height of a primary button.
    static let buttonHeight: CGFloat = 52
    /// Default height of a compact control (chip, speed toggle, counter).
    static let controlHeight: CGFloat = 36
    /// Default width of a `ProgressRing`.
    static let ringSize: CGFloat = 72
    /// The video stage's aspect ratio (16:9).
    static let videoAspect: CGFloat = 16.0 / 9.0
}

// MARK: - Time formatting
enum Format {
    /// `m:ss`, or `h:mm:ss` past an hour. Used by every scrubber and counter.
    ///
    /// - Parameter seconds: A duration or position. Negative and non-finite
    ///   inputs render as `0:00` rather than crashing a SwiftUI body.
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// A fraction in `0...1` as a whole percentage, e.g. `72%`.
    static func percent(_ fraction: Double) -> String {
        let clamped = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// A count with a thousands separator, e.g. `12,480`.
    static func count(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}
