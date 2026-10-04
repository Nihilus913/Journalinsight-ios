import Foundation
import Testing
import JICore
import JIDesign
import JIPersistence
@testable import JIFeatures

// W-B57-W3 L4 guard rows — the fixed bugs on the screens this lane edits (Decide, GateRationale,
// Recovery, KpiDetail, Trends, GateConfig, RootTabView). Written first; they pass on the base and
// must stay green once the recovery score card, the normal bands and the Sleep-goal copy land.

private func b57w3Source(_ relative: String) throws -> String {
    let pkg = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: pkg.appending(path: relative), encoding: .utf8)
}

private func b57w3Signal(_ key: String, _ label: String, value: Double?, status: GateSignalStatus,
                         threshold: Double = 27, direction: GateSignalDirection = .min) -> GateSignal {
    GateSignal(key: key, label: label, value: value, unit: key == "sleep_h" ? "h" : "ms", threshold: threshold,
               direction: direction, status: status)
}

struct B57W3GuardTests {
    // MARK: BUG-29 — GateRationale: time, WHY TODAY IS, status words (board 03)

    @Test func bug29_rationaleHeaderTimeAndWords() {
        #expect(gateRationaleHeaderLabel == "WHY TODAY IS")
        #expect(gateRationaleNavigationTitle.isEmpty)   // no "Readiness rati…" title at AX3
        #expect(gateRationaleComputedTime("2026-09-25T05:41:00Z", timeZone: TimeZone(identifier: "UTC")!) == "05:41")
        #expect(gateRationaleComputedTime(nil) == nil)
        let sentence = gateRationaleWhySentence(signals: [
            b57w3Signal("sleep_h", "Sleep", value: 7.4, status: .pass, threshold: 7),
            b57w3Signal("hrv", "HRV", value: 22, status: .amber),
        ])
        #expect(sentence == "Sleep cleared the 7 h goal and overnight HRV is low.")
        #expect(gateRationaleWhySentence(signals: nil) == nil)
    }

    @Test func bug29_countedRowsSayNoDataNeverAPass() {
        let rows = gateRationaleCountedRows(signals: [b57w3Signal("hrv", "HRV", value: nil, status: .pass)], normals: [:], load: nil)
        #expect(rows.first?.status == .missing(.noData))
        #expect(rows.first?.sentence == "No overnight value yet. Left out, not counted as bad.")
        #expect(rows.last?.id == "load")
    }

    // MARK: BUG-09 — KpiDetail push terminates (owned model, no phase animation)

    @Test func bug09_kpiDetailOwnsItsModelAndDoesNotAnimateThePhase() throws {
        let body = try b57w3Source("Sources/JIFeatures/Kpi/KpiDetailView.swift")
        #expect(body.contains("@State private var model: KpiDetailViewModel"))
        #expect(body.contains("_model = State(initialValue: model)"))
        #expect(!body.contains(".animation(JIMotion.standard, value: model.phase)"))
        #expect(!body.contains("value: model.phase)"))
    }

    // MARK: BUG-22 — the nutrition segment switches title / trend / alert

    @Test @MainActor func bug22_segmentSwitchesTheScreensMetric() async throws {
        let vm = KpiDetailViewModel(metric: .protein, healthProvider: KpiFakeProvider(), nutritionProvider: KpiFakeProvider(),
                                    targetsProvider: KpiFakeProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()))
        await vm.load()
        vm.selectMetric(.fat)
        #expect(vm.metric == .fat)
        #expect(vm.def.label == "Fat")
        vm.selectMetric(.hrv)   // not a nutrition macro: ignored
        #expect(vm.metric == .fat)
        #expect(kpiDetailShowsLineTrend(.fat) == false)
    }

    // MARK: PF-01 — superseded by W-DECIDE-HYBRID H-1: no bar pinned above the tab bar

    @Test func pf01_decideActionsSitInTheScrollAboveTheTabBar() throws {
        #expect(decideScrollBottomClearance(.compact) == tabBarBottomClearance(.compact))
        #expect(decideButtonRoles(showsAdjust: true) == [.primary, .secondary])
        let body = try b57w3Source("Sources/JIFeatures/Today/DecideView.swift")
        #expect(!body.contains(".safeAreaInset(edge: .bottom"))
        #expect(!body.contains("\"today.decide.actions\""))
    }

    // MARK: PF-04 — one sync-pill rule (newer of hub sync / HealthKit upload) on the touched screens

    @Test func pf04_oneRuleIsTheNewerInstant() {
        let hub = Date(timeIntervalSince1970: 1_790_300_000)
        #expect(oneSyncPillDate(injected: hub, lastUpload: hub.addingTimeInterval(60)) == hub.addingTimeInterval(60))
        #expect(oneSyncPillDate(injected: hub, lastUpload: nil) == hub)
        #expect(oneSyncPillDate(injected: nil, lastUpload: nil) == nil)
    }

    @Test func pf04_touchedScreensNeverPillTheFetchTime() throws {
        let recovery = try b57w3Source("Sources/JIFeatures/Recovery/RecoveryView.swift")
        #expect(recovery.contains("OneSyncedPill("))
        #expect(!recovery.contains("SyncedPill(date: model.fetchedAt"))
        let decide = try b57w3Source("Sources/JIFeatures/Today/DecideView.swift")
        #expect(decide.contains("SyncedPill(date: syncedAt"))
        #expect(!decide.contains("SyncedPill(date: fetchedAt"))
        // The shell hands Decide Today's one rule and every tab stack the same instant.
        let shell = try b57w3Source("../../App/RootTabView.swift")
        #expect(shell.contains("syncedAt: model.syncedAt"))
        #expect(shell.contains(".environment(\\.jiSyncedAt, Self.tabSyncedAt(todayModel))"))
    }
}
