import SwiftUI

/// The app's single card treatment: a filled surface at ``Radius/card``, a
/// hairline border in light mode, and a soft shadow in dark mode.
///
/// Why the split: in light mode a 1pt hairline separates a white card from a
/// warm off-white page more cleanly than any shadow — a shadow on a light
/// surface reads as a smudge. In dark mode there is no page-to-card luminance
/// difference to draw a border against, so the shadow does the lifting instead
/// and the border is dropped to keep the edge crisp.
struct CardStyle: ViewModifier {
    /// Lifts the card one level, for a card that should read as floating above
    /// its siblings (a popover, a selected row).
    var isRaised: Bool = false
    /// Tints the fill, e.g. with `Palette.brandSoft` on a selected topic.
    var fill: Color = Palette.surface

    @Environment(\.colorScheme) private var colorScheme

    private var cornerRadius: CGFloat { Radius.card }

    func body(content: Content) -> some View {
        content
            .padding(Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .modifier(EdgeDefinition(colorScheme: colorScheme, raised: isRaised))
            .shadow(
                color: colorScheme == .dark
                    ? Palette.shadow
                    : .clear,
                radius: isRaised ? 18 : 10,
                x: 0,
                y: isRaised ? 8 : 3
            )
    }
}

/// The border half of ``CardStyle``, split out so the shadow can be applied
/// after the fill and the border does not get shadowed along with it.
private struct EdgeDefinition: ViewModifier {
    let colorScheme: ColorScheme
    let raised: Bool

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content
        } else {
            content.overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.separator, lineWidth: 1)
            )
        }
    }
}

extension View {
    /// The default surface for a discrete block of content.
    func cardStyle(isRaised: Bool = false, fill: Color = Palette.surface) -> some View {
        modifier(CardStyle(isRaised: isRaised, fill: fill))
    }
}

// MARK: - Liquid Glass
//
// Glass is a *layer*, not a background. It belongs on floating surfaces the
// finger is about to touch — the transport bar, the floating action cluster,
// the tab-adjacent toolbar — where a real material gives the control a sense of
// sitting above the content it covers.
//
// It does not belong on the page background, on a topic card, or on a scroll
// row. Glassing a scrolling list makes the content unreadable and the
// performance unpredictable. Every use in this app is a small, static cluster
// of tappable controls.
//
// Three rules the app follows, because getting them wrong is what makes Liquid
// Glass look broken rather than expensive:
//   1. `.glassEffect` is applied *after* layout and appearance modifiers, never
//      before, so the glass samples the already-rendered content underneath.
//   2. Related glass views live inside one `GlassEffectContainer`, so the system
//      can merge them into a single refractive layer instead of stacking
//      independent ones that disagree at their seams.
//   3. `.interactive()` is only on genuinely tappable controls. On decoration it
//      makes the whole cluster respond to a press, which reads as a bug.

/// Wraps `content` in the system's Liquid Glass on iOS 26 and later, and in a
/// real blur material before that.
///
/// - Parameter content: The controls to make glassy.
/// - Returns: A view that adapts to the running system.
//
// The container is applied on *both* paths. On iOS 26 the system uses it to
// merge the cluster's glass into one refractive layer; before that it is a
// no-op wrapper, and the material fallback does the visual work. One code path
// either way, so the two systems cannot drift apart.
@ViewBuilder
func glassSurface<Content: View>(
    @ViewBuilder content: () -> Content
) -> some View {
    if #available(iOS 26, *) {
        // `spacing:` is the gap *between* the container's glass elements, not a
        // corner radius — so it comes from the spacing scale.
        GlassEffectContainer(spacing: Spacing.sm) {
            content()
                .glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
        }
    } else {
        // The fallback is a genuine material, not a flat fill: on iOS 17–25 a
        // flat colour would give no sense of translucency at all, and the
        // control would read as a card rather than as something floating.
        content().modifier(GlassControl())
    }
}

/// A tappable glass control. Same material as ``glassSurface``, plus the
/// system's press response, plus a `shadow` for separation on older systems.
///
/// The `.interactive()` is *not* applied here: whether a given control
/// responds to press is the caller's decision, and a whole cluster reacting at
/// once is the mistake `.interactive()` invites.
struct GlassControl: ViewModifier {
    /// Whether pressing this control animates it. Set `true` only on a single
    /// real button, never on a container.
    var isInteractive: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            // On iOS 26 the system material already honours Reduce
            // Transparency, so there is nothing to flatten by hand here.
            if isInteractive {
                content.glassEffect(.regular.interactive, in: .rect(cornerRadius: Radius.card))
            } else {
                content.glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
            }
        } else if reduceTransparency {
            // Before iOS 26 the material is ours to substitute, and a
            // user with Reduce Transparency on has asked for exactly this.
            content.background(
                Palette.surfaceRaised,
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Palette.separator, lineWidth: 0.5)
                )
                .shadow(color: Palette.shadow, radius: 8, x: 0, y: 2)
                .compositingGroup()
        }
    }
}

extension View {
    /// Places this view on a Liquid Glass surface, grouping it with any sibling
    /// glass in the same cluster.
    ///
    /// Applied *after* the view's own layout and appearance modifiers — the
    /// glass samples what is already there.
    func glassCard(isInteractive: Bool = false) -> some View {
        modifier(GlassControl(isInteractive: isInteractive))
    }

    /// A glass surface whose content is filled edge to edge and padded, for
    /// the common "floating bar" case.
    func glassBar(padding: CGFloat = Spacing.md) -> some View {
        self
            .padding(padding)
            .glassCard()
    }
}
