import SwiftUI

/// Section title styled with the Liquid Glass treatment.
///
/// ponytail: the shared `SectionHeader` in App/Components is the plain variant.
/// The profile screen wants the floating glass treatment on its own headers, and
/// the only place I can legally add it is this folder.
// TODO(design-system-lane): if `SectionHeader` grows a `style:` parameter, delete this and call it instead.
struct GlassSectionHeader: View {

    let title: String
    var subtitle: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(AppFont.display(.title3, weight: .bold))
                .foregroundStyle(.primary)

            if let subtitle {
                Text(subtitle)
                    .font(AppFont.display(.subheadline, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .liquidGlass(cornerRadius: Radius.pill)
        .accessibilityElement(children: .combine)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: title)
    }
}

extension View {

    /// Applies the iOS 26 floating glass treatment, with a material fallback.
    ///
    /// Deliberately gated behind `#available` rather than a flag: the material
    /// is not an approximation of glass, it is what the app looked like last
    /// year, and it is honest.
    ///
    /// - Parameter cornerRadius: The corner radius to use on both paths.
    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
