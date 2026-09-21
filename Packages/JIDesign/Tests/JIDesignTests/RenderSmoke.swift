import SwiftUI
import Testing
@testable import JIDesign

/// Renders a view off-screen in both themes and both colour schemes; fails if SwiftUI cannot
/// produce an image (a crash in `body`, a missing environment, an unavailable API).
@MainActor
func expectRenders<V: View>(_ name: Comment, width: CGFloat = 320, height: CGFloat = 200, @ViewBuilder _ view: () -> V) {
    for theme in JITheme.allCases {
        for scheme in [ColorScheme.light, .dark] {
            let content = view().frame(width: width, height: height).jiTheme(theme).environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: content)
            #expect(renderer.cgImage != nil, "\(name) renders in \(theme)/\(scheme)")
        }
    }
}
