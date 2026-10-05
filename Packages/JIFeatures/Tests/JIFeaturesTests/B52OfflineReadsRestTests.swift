import Foundation
import Testing
import JICore
@testable import JIFeatures

/// B-52 p3 (reads: rest): every non-training screen loads from cache with the hub down, and a cold
/// cache reads as an explicit "No cached data yet" — never blank, never a fabricated value.
///
/// Two layers:
/// 1. Copy: `OfflineReadCopy` maps an offline failure to the cold-cache line and leaves named hub
///    answers (401, 502 YAZIO, 404 …) to the screen's own copy.
/// 2. Read-path lint (source scan): no hub read can bypass the read-through cache — the only
///    `session.data(for:)` is inside `HubClient.swift`, and App/JIFeatures never talk to the
///    network themselves; every rest-of-app screen's error copy for `.network` is the cold-cache
///    line (the screen only reaches `describe` with nothing to show).
@Suite struct B52OfflineReadsRestTests {
    static let root = B52NoDirectSendLintTests.root

    // MARK: copy

    @Test func offlineFailuresMapToTheColdCacheLine() {
        let named: (Error) -> String = { _ in "named" }
        #expect(OfflineReadCopy.emptyFailure(HubError.network("refused"), otherwise: named) == OfflineReadCopy.coldCache)
        #expect(OfflineReadCopy.emptyFailure(HubError.http(status: 503, detail: nil), otherwise: named) == OfflineReadCopy.coldCache)
        #expect(OfflineReadCopy.emptyFailure(HubError.unauthorized, otherwise: named) == "named")
        #expect(OfflineReadCopy.emptyFailure(HubError.yazioAuthExpired(detail: "x"), otherwise: named) == "named")
        #expect(OfflineReadCopy.emptyFailure(HubError.http(status: 404, detail: nil), otherwise: named) == "named")
        #expect(OfflineReadCopy.coldCache.hasPrefix(OfflineReadCopy.coldCacheTitle))
    }

    @Test @MainActor func dataQualityColdCacheWithTheHubDownSaysNoCachedDataYet() async {
        let model = DataQualityViewModel(provider: B52DeadDataQuality())
        await model.load()
        #expect(model.phase == .error(OfflineReadCopy.coldCache))
        #expect(model.report == nil)
    }

    // MARK: read-path lint

    private static func swiftFiles(under rel: String) -> [(rel: String, text: String)] {
        let base = root.appending(path: rel)
        guard let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        var out: [(String, String)] = []
        for case let url as URL in e where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            out.append((url.path.replacingOccurrences(of: root.path + "/", with: ""), text))
        }
        return out
    }

    @Test func noHubReadBypassesTheReadThroughCache() {
        let hub = Self.swiftFiles(under: "Packages/JIHub/Sources/JIHub")
        #expect(!hub.isEmpty, "source scan found no JIHub files — wrong root?")
        for f in hub where !f.rel.hasSuffix("/HubClient.swift") {
            #expect(!f.text.contains("session.data("), "\(f.rel): raw request bypasses HubClient.get's cache")
            #expect(!f.text.contains("URLRequest("), "\(f.rel): raw request bypasses HubClient.get's cache")
        }
        let features = Self.swiftFiles(under: "Packages/JIFeatures/Sources/JIFeatures") + Self.swiftFiles(under: "App")
        #expect(!features.isEmpty)
        for f in features {
            #expect(!f.text.contains(".data(for:"), "\(f.rel): screen code talks to the network itself")
        }
    }

    /// The rest-of-app screens (card B-52 p3 scope). Training/Planner/Calendar/Workouts are p2's.
    static let restScreens = [
        "Today/TodayViewModel.swift", "Energy/EnergyViewModel.swift", "Recovery/RecoveryViewModel.swift",
        "Goals/GoalsSetupViewModel.swift", "GateRationale/GateRationaleViewModel.swift",
        "Kpi/KpiListViewModel.swift", "Kpi/KpiDetailViewModel.swift", "Nutrition/NutritionViewModel.swift",
        "DataQuality/DataQualityViewModel.swift",
    ]

    @Test func everyRestScreenSaysNoCachedDataYetWhenOfflineAndEmpty() throws {
        for name in Self.restScreens {
            let url = Self.root.appending(path: "Packages/JIFeatures/Sources/JIFeatures/\(name)")
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("case .network: OfflineReadCopy.coldCache"), "\(name): offline+empty must read as the cold cache")
            #expect(!text.contains("is the Mac awake"), "\(name): old hub-unreachable copy")
        }
    }
}

private struct B52DeadDataQuality: DataQualityProviding {
    func dataQuality() async throws -> DataQualityReport { throw HubError.network("Could not connect to the server.") }
}
