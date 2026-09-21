import SwiftUI

/// The card. Classic: the caller's `radius` on the level's fill (unchanged since W2a).
/// Native (B-33 §2): inset grouped cell — radius comes from the level, `radius:` is ignored,
/// no outer hairline.
public struct Surface<Content: View>: View {
    private let level: Int, radius: CGFloat, padding: CGFloat, content: Content
    @Environment(\.jiTheme) private var theme
    public init(level: Int = 1, radius: CGFloat = JIRadius.card, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.level = level; self.radius = radius; self.padding = padding; self.content = content()
    }
    private var style: (fill: JIColorRole, radius: JIRadiusRole) { surfaceStyle(level: level, theme: theme) }
    private var cornerRadius: CGFloat { theme == .native ? theme.radius(style.radius) : radius }
    public var body: some View {
        content.padding(padding)
            .background(theme.color(style.fill), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
