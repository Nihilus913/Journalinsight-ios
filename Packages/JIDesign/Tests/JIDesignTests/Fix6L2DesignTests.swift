import SwiftUI
import Testing
@testable import JIDesign

// W-FIX6 L2: F6-6 (AX3 row titles wrap), F6-5 (the "How JI …" chevron row), F6-14/15 (toolbar
// buttons are system toolbar items, pushed screens get the soft top edge).

private func designSource(_ relative: String) throws -> String {
    let pkg = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: pkg.appending(path: relative), encoding: .utf8)
}

// F6-6: "How the morni…" at AX3 — a row title never truncates at accessibility sizes.
@Test func f66ChevronRowTitleWrapsAtAccessibilitySizes() {
    #expect(JIChevronRowMetrics.titleLineLimit(.large) == 1)
    #expect(JIChevronRowMetrics.titleLineLimit(.xxxLarge) == 1)
    #expect(JIChevronRowMetrics.titleLineLimit(.accessibility3) == nil)
    #expect(JIChevronRowMetrics.titleLineLimit(.accessibility5) == nil)
    #expect(JIChevronRowMetrics.stacksValue(.accessibility3))
    #expect(!JIChevronRowMetrics.stacksValue(.large))
}

@Test @MainActor func f66ChevronRowRendersAtAX3() {
    // (macOS ImageRenderer does not scale type, so the growth itself is checked on the sim.)
    expectRenders("JIChevronRow AX3") {
        JIChevronRow(title: "How the morning call works", value: "Every signal", systemImage: "questionmark.circle")
            .environment(\.dynamicTypeSize, .accessibility3)
    }
}

// F6-5: the chevron row that replaces the "How JI … ›" text link.
@Test @MainActor func f65HowWeCalculateRowRenders() {
    expectRenders("JIHowWeCalculateRow") {
        JIHowWeCalculateRow("How JI learns your normal", title: "Your normal", steps: [.init(title: "a", body: "b")])
    }
}

// F6-14 / F6-15: toolbar buttons are plain toolbar items (the system draws the one glass), and
// the back-button modifier gives every pushed screen the soft top scroll edge.
@Test @MainActor func f614ToolbarButtonRendersAndBackUsesIt() throws {
    expectRenders("JIToolbarButton") { JIToolbarButton("checkmark", label: "Done") {} }
    expectRenders("jiSoftTopEdge") { Text("x").jiSoftTopEdge() }
    let body = try designSource("Sources/JIDesign/GlassButton.swift")
    #expect(body.contains("JIToolbarButton(\"chevron.left\", label: \"Back\")"))
    #expect(!body.contains("JIGlassButton(\"chevron.left\", label: \"Back\")"))
}
