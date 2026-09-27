import SwiftUI
import Testing
import JIDesign
@testable import JIFeatures

// W-GUI F6 — `ScreenScroll` renders in both branches with the soft edge effect applied on the
// live one (the offscreen branch stays a plain stack, so the sweep captures real content).
@MainActor
@Test func screenScrollRendersInBothBranches() {
    for offscreen in [false, true] {
        let content = ScreenScroll { VStack { ForEach(0..<40) { Text("row \($0)") } } }
            .environment(\.jiOffscreenRender, offscreen)
            .frame(width: 320, height: 400)
            .jiTheme(.native)
        #expect(ImageRenderer(content: content).cgImage != nil, "ScreenScroll offscreen=\(offscreen)")
    }
}

@MainActor
@Test func softEdgesModifierRenders() {
    let content = ScrollView { Text("x") }.modifier(JISoftScrollEdges()).frame(width: 100, height: 100)
    #expect(ImageRenderer(content: content).cgImage != nil)
}
