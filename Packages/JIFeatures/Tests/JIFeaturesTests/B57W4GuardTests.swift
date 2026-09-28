import Foundation
import SwiftUI
import Testing
import JICore
import JIDesign
import JIPersistence
@testable import JIFeatures
#if canImport(UIKit)
import UIKit
#endif

// W-B57-W4 lane LC guard tests (written first, green on the wave base): fixed rows whose files
// LC touches. BUG-09 (KpiDetail layout loop), BUG-31 (GateConfig "Use recommended" accent).
// BUG-21 (My KPIs Done) is pinned in AppTests/RootTabShellTests.swift (the sheet lives in the App).

private func guardSource(_ relative: String) throws -> String {
    let pkg = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: pkg.appending(path: relative), encoding: .utf8)
}

// MARK: - BUG-31: the rules reset (W-TGT: Targets "Reset rules to recommended", was GateConfig's
// "Use recommended") is a JI button style, never a metric colour

@Test func bug31_useRecommendedIsTheAccentPrimaryButton() throws {
    let body = try guardSource("Sources/JIFeatures/Targets/TargetsView.swift")
    let button = try #require(body.range(of: "Button(TargetsRows.resetRules)"))
    let tail = body[button.upperBound...].prefix(300)
    #expect(tail.contains(".buttonStyle(.jiSecondary)") || tail.contains(".buttonStyle(.jiPrimary)"))
    // No hard-coded metric / system colour on the CTA.
    #expect(!tail.contains(".tint(.blue)") && !tail.contains("Color.blue") && !tail.contains(".hrv"))
}

@Test @MainActor func bug31_theAccentRoleFollowsTheChosenAccent() {
    let saved = JIAccent.shared.color
    defer { JIAccent.shared.color = saved }
    JIAccent.shared.color = .teal
    // `.jiPrimary` fills with `.info`; `.info` is the user's accent.
    #expect(JITheme.native.color(.info) == .teal)
}

// MARK: - BUG-09: KpiDetail pushed for HRV (the screen LC extends) loads and its layout settles

#if canImport(UIKit)
@Test @MainActor func bug09_hrvDetailLoadsAndLayoutTerminates() async throws {
    let model = KpiDetailViewModel(
        metric: .hrv, healthProvider: KpiFakeProvider(), nutritionProvider: KpiFakeProvider(),
        targetsProvider: KpiFakeProvider(), cache: OfflineCache(db: try AppDatabase.inMemory())
    )
    // Hosted the way the existing BUG-09 test hosts it (no NavigationStack: a stack in a bare
    // test window hung the full parallel iOS run on the base too — a harness artifact).
    let host = UIHostingController(rootView: KpiDetailView(model: model))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
    window.rootViewController = host
    window.makeKeyAndVisible()
    for _ in 0..<100 where model.phase != .loaded {
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(model.phase == .loaded)
    // A layout loop never returns from layoutIfNeeded (the hang in BUG-09); these must.
    for _ in 0..<5 { host.view.layoutIfNeeded() }
    window.isHidden = true
}
#endif

// MARK: - W-B57-W4 fixer: no bare text links (W-GUI DEV-07) on the W4 surfaces

/// Every one of these actions is a chevron row or a JI button style — never a tinted text link.
@Test(arguments: [
    ("Sources/JIFeatures/GateConfig/GateConfigView.swift", "\"Walk me through it again\""),
    ("Sources/JIFeatures/Targets/TargetsView.swift", "is still right\")"),
    ("Sources/JIFeatures/Kpi/DaytimeHrvSection.swift", "\"Change answer\""),
])
func dev07_w4ActionsAreRowsOrButtonsNotTextLinks(file: String, literal: String) throws {
    let body = try guardSource(file)
    let hit = try #require(body.range(of: literal))
    let before = String(body[..<hit.lowerBound].suffix(200))
    let after = String(body[hit.upperBound...].prefix(250))
    let window = before + literal + after
    #expect(window.contains("JIChevronRow") || window.contains(".buttonStyle(.jiSecondary)")
            || window.contains(".buttonStyle(.jiPrimary)"), "\(literal) is a bare text link")
    #expect(!window.contains(".borderless"))
}
