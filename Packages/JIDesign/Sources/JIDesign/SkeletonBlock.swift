import SwiftUI

public struct SkeletonBlock: View {
    private let width: CGFloat?, height: CGFloat
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.jiTheme) private var theme
    public init(width: CGFloat? = nil, height: CGFloat = 16) { self.width = width; self.height = height }
    public var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(theme.color(.surface3))
            .frame(width: width, height: height)
            .opacity(pulse ? 0.45 : 0.9)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
            .accessibilityHidden(true)
    }
}
