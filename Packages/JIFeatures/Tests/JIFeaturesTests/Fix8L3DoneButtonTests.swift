import Foundation
import Testing

// W-FIX8 L3 G-1 (device 2026-09-28): the On Today sheet's ✓ Done sat crammed in the top-right,
// under the sheet corner. Root cause = the W-FIX6 F6-14 trap left in two sheets: a `JIGlassButton`
// (its own 44 pt @ScaledMetric glass disc) inside a `ToolbarItem`, whose glass the system already
// draws — glass inside glass that outgrows the bar (worse at AX3). Toolbar items use
// `JIToolbarButton`; `JIGlassButton` stays in the content layer.

private let fix8Repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()   // Packages/JIFeatures
    .deletingLastPathComponent().deletingLastPathComponent()                               // repo root

private func fix8Source(_ relative: String) throws -> String {
    try String(contentsOf: fix8Repo.appending(path: relative), encoding: .utf8)
}

/// Every `ToolbarItem(...) { ... }` body in `source` that draws a `JIGlassButton`.
func toolbarItemsWithGlassButton(_ source: String) -> [String] {
    var hits: [String] = []
    var rest = source[...]
    while let open = rest.range(of: "ToolbarItem(") {
        let after = rest[open.upperBound...]
        // The item's content: up to the next ToolbarItem / closing of the toolbar builder (bounded).
        let next = after.range(of: "ToolbarItem(")?.lowerBound ?? after.endIndex
        let window = after[..<next].prefix(400)
        if window.contains("JIGlassButton(") { hits.append(String(window.prefix(160))) }
        rest = after
    }
    return hits
}

@Test func g1GuardCatchesGlassInsideAToolbarItem() {
    let bad = "ToolbarItem(placement: .confirmationAction) {\n JIGlassButton(\"checkmark\", label: \"Done\") { x() } }"
    let good = "ToolbarItem(placement: .confirmationAction) {\n JIToolbarButton(\"checkmark\", label: \"Done\") { x() } }"
    #expect(toolbarItemsWithGlassButton(bad).count == 1)
    #expect(toolbarItemsWithGlassButton(good).isEmpty)
}

@Test func g1NoSheetOrScreenPutsAGlassButtonInItsToolbar() throws {
    let fm = FileManager.default
    var offenders: [String] = []
    for root in ["App", "Packages/JIFeatures/Sources", "Packages/JIDesign/Sources"] {
        let base = fix8Repo.appending(path: root)
        guard let files = fm.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
        for case let url as URL in files where url.pathExtension == "swift" {
            let body = try String(contentsOf: url, encoding: .utf8)
            if !toolbarItemsWithGlassButton(body).isEmpty { offenders.append(url.lastPathComponent) }
        }
    }
    // Pushed screens with the same trap, outside W-FIX8's bounded scope (reported as a follow-up
    // row; remove each name here when its screen moves to JIToolbarButton). No NEW offenders.
    let knownPushed: Set<String> = ["GoalsView.swift", "TrendsView.swift", "RecoveryView.swift"]
    #expect(Set(offenders).subtracting(knownPushed).isEmpty, "glass inside a toolbar item: \(offenders)")
    #expect(!offenders.contains("RootTabView.swift") && !offenders.contains("EditTodayView.swift"))
}

@Test func g1OnTodayAndEditTodaySheetsUseTheToolbarDone() throws {
    let root = try fix8Source("App/RootTabView.swift")
    #expect(root.contains("JIToolbarButton(\"checkmark\", label: \"Done\") { showKpiList = false }"))
    let edit = try fix8Source("Packages/JIFeatures/Sources/JIFeatures/EditToday/EditTodayView.swift")
    #expect(edit.contains("JIToolbarButton(\"checkmark\", label: \"Done\", action: onDone)"))
    #expect(edit.contains("ToolbarItem(placement: .confirmationAction)"))
}
