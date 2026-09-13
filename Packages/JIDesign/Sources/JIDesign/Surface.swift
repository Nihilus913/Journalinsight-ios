import SwiftUI

public struct Surface<Content: View>: View {
    private let level: Int, radius: CGFloat, padding: CGFloat, content: Content
    public init(level: Int = 1, radius: CGFloat = JIRadius.card, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.level = level; self.radius = radius; self.padding = padding; self.content = content()
    }
    private var fill: Color { switch level { case 2: JIColor.surface2; case 3: JIColor.surface3; default: JIColor.surface } }
    public var body: some View {
        content.padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
