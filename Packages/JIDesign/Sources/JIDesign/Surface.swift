import SwiftUI

/// The card (B-33 §2): an inset grouped cell — the radius comes from the level, never the
/// caller. Phase C removed the `radius:` parameter with the classic language that honoured it.
public struct Surface<Content: View>: View {
    private let level: Int, padding: CGFloat, content: Content
    @Environment(\.jiTheme) private var theme
    public init(level: Int = 1, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.level = level; self.padding = padding; self.content = content()
    }
    private var style: (fill: JIColorRole, radius: JIRadiusRole) { surfaceStyle(level: level, theme: theme) }
    private var cornerRadius: CGFloat { theme.radius(style.radius) }
    public var body: some View {
        content.padding(padding)
            .background(theme.color(style.fill), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
