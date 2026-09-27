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

// MARK: - BUG-31: GateConfig "Use recommended" is the accent (green by default), not a metric colour

@Test func bug31_useRecommendedIsTheAccentPrimaryButton() throws {
    let body = try guardSource("Sources/JIFeatures/GateConfig/GateConfigView.swift")
    let button = try #require(body.range(of: "Text(\"Use recommended\")"))
    let tail = body[button.upperBound...].prefix(300)
    #expect(tail.contains(".buttonStyle(.jiPrimary)"))
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
@Test(.timeLimit(.minutes(1))) @MainActor func bug09_hrvDetailLoadsAndLayoutTerminates() async throws {
    let model = KpiDetailViewModel(
        metric: .hrv, healthProvider: KpiFakeProvider(), nutritionProvider: KpiFakeProvider(),
        targetsProvider: KpiFakeProvider(), cache: OfflineCache(db: try AppDatabase.inMemory())
    )
    let host = UIHostingController(rootView: NavigationStack { KpiDetailView(model: model) })
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
