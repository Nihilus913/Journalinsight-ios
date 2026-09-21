import SwiftUI
import Testing
@testable import JIDesign

@Test func rowMinHeightIsTheSystem44() {
    #expect(JIRow<EmptyView>.minHeight == 44)
}

@Test @MainActor func rowRenders() {
    expectRenders("JIRow") { JIRow(title: "Sleep score", subtitle: "Last night", systemImage: "bed.double.fill", tint: .purple) { Text("85") } }
    expectRenders("JIRow plain") { JIRow(title: "Version") }
}
