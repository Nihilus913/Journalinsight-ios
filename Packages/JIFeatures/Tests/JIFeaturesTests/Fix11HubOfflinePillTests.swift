import Foundation
import Testing
@testable import JIFeatures

// W-FIX11 H1-15 (+H2-05) verifier FAIL: with the hub down, Recovery and Nutrition still showed the
// green "✓ Synced 09:00" pill next to "Offline · last 9:00", because only Today, Training and the
// gate injected `jiHubOffline`. Every screen that shows a sync pill AND knows `hubReachable` must
// inject it, so the pill can never read "today" while the banner reads offline.

private func fix11OfflineSource(_ relative: String) throws -> String {
    let pkg = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: pkg.appending(path: relative), encoding: .utf8)
}

struct Fix11HubOfflinePillTests {
    @Test(arguments: [
        "Sources/JIFeatures/Recovery/RecoveryView.swift",
        "Sources/JIFeatures/Nutrition/NutritionView.swift",
        "Sources/JIFeatures/Energy/EnergyView.swift",
        "Sources/JIFeatures/Kpi/KpiDetailView.swift",
        "Sources/JIFeatures/Kpi/KpiListView.swift",
        "Sources/JIFeatures/Today/TodayView.swift",
        "Sources/JIFeatures/Training/TrainingView.swift",
    ])
    func h1_15_everyHubScreenInjectsOffline(_ path: String) throws {
        let body = try fix11OfflineSource(path)
        #expect(body.contains(".environment(\\.jiHubOffline, !model.hubReachable)"), "\(path) must inject jiHubOffline")
    }
}
