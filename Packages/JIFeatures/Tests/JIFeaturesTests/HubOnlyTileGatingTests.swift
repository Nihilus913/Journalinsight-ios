import Foundation
import SwiftUI
import Testing
import JICore
import JICompute
import JIDesign
import JIHealthKit
import JIPersistence
@testable import JIFeatures

/// W-OFFLINE OFF-2 (B-50 slice 1): a tile whose ParityRegistry key is `.hubOnly` (`hrv`,
/// `body_battery`, `readiness_hub_input_2_2`) says "Garmin value — needs the hub" when the active
/// provider is not the hub — never "—"/0/empty, and never a value approximated or carried over
/// from a cached hub row (decision #23). Under the hub every tile keeps its real value.
private let offNow = ISO8601DateFormatter().date(from: "2026-10-07T06:00:00Z")!

private let offDays: [RecoveryDay] = [
    RecoveryDay(date: "2026-10-07", sleepScore: 82, sleepDurationSec: 27000, rhrBpm: 52, bodyBatteryAvg: 64,
                readinessScore: 71, acwr: 1.05, hrvWeeklyAvg: 40, hrvRmssdMs: 42, bodyBatteryMin: 18, bodyBatteryMax: 88),
    RecoveryDay(date: "2026-10-06", sleepScore: 78, sleepDurationSec: 25000, rhrBpm: 54, bodyBatteryAvg: 60,
                readinessScore: 66, acwr: 1.02, hrvWeeklyAvg: 39, hrvRmssdMs: 38, bodyBatteryMin: 20, bodyBatteryMax: 80),
]

/// The same rows from two sources: the hub (`.hubAll`) and the on-device reader
/// (`HealthKitProvider`'s own `appleWatchCapabilities` bitmap).
private struct OffStub: HealthDataProvider {
    let capabilities: DataCapability
    func health() async throws -> HealthResponse { HealthResponse(status: "ok") }
    func gate(windowDays: Int) async throws -> GateResponse { try await MockDataProvider().gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try await MockDataProvider().morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await MockDataProvider().morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { offDays }
    func syncStatus() async throws -> SyncStatus { SyncStatus(lastSync: nil) }
}

@MainActor
@Suite struct HubOnlyTileGatingTests {
    static let onDevice = DataCapability.appleWatchCapabilities
    static let gatedTiles = ["hrv", "body_battery", "readiness"]

    // MARK: the registry drives the gate

    @Test func everyHubOnlyRegistryKeyHasAGatedTile() {
        let hubOnlyKeys = Set(ParityRegistry.entries.filter { $0.value.source == .hubOnly }.keys)
        #expect(hubOnlyKeys == ["hrv", "body_battery", "readiness_hub_input_2_2"])
        #expect(Set(hubOnlyTileRegistryKeys.values) == hubOnlyKeys)
        for id in Self.gatedTiles {
            #expect(hubOnlyTileNeedsHub(id, capabilities: Self.onDevice), "\(id) under HealthKitProvider")
            #expect(!hubOnlyTileNeedsHub(id, capabilities: .hubAll), "\(id) under the hub")
        }
        // A computed / hub metric is never gated.
        for id in ["rhr", "sleep", "steps", "acwr", "kcal"] { #expect(!hubOnlyTileNeedsHub(id, capabilities: Self.onDevice)) }
        #expect(JIMissingReason.needsHub.rawValue == "Garmin value — needs the hub")
    }

    // MARK: Today

    @Test func todayHubOnlyTilesSayNeedsTheHubOnDevice() async throws {
        let model = TodayViewModel(provider: OffStub(capabilities: Self.onDevice), cache: OfflineCache(db: try AppDatabase.inMemory()),
                                   now: { offNow })
        await model.load()
        let byId = Dictionary(uniqueKeysWithValues: model.gridChips.map { ($0.id, $0) })
        for id in Self.gatedTiles {
            let chip = try #require(byId[id])
            #expect(chip.needsHub && chip.value == nil && chip.points.isEmpty, "\(id)")
            let spec = todaySummaryCardSpec(for: chip)
            #expect(spec.value == nil && spec.sparkline.isEmpty && spec.timestamp == nil, "\(id)")
            #expect(spec.missingCopy == JIMissingReason.needsHub.rawValue, "\(id)")
            #expect(editTodaySquare(id, chips: model.gridChips, badge: .none).status == .missing(.needsHub), "\(id)")
        }
        // Non-hub-only tiles keep the on-device value.
        #expect(byId["rhr"]?.value == 52 && byId["rhr"]?.needsHub == false)
    }

    @Test func todayHubOnlyTilesShowTheRealValueUnderTheHub() async throws {
        let model = TodayViewModel(provider: OffStub(capabilities: .hubAll), cache: OfflineCache(db: try AppDatabase.inMemory()),
                                   now: { offNow })
        await model.load()
        let byId = Dictionary(uniqueKeysWithValues: model.gridChips.map { ($0.id, $0) })
        #expect(byId["hrv"]?.value == 42 && byId["hrv"]?.needsHub == false)
        #expect(byId["body_battery"]?.value == 64 && byId["body_battery"]?.needsHub == false)
        #expect(byId["readiness"]?.value == 71 && byId["readiness"]?.needsHub == false)
        let spec = todaySummaryCardSpec(for: try #require(byId["body_battery"]))
        #expect(spec.value == "64" && spec.missingCopy == nil)
    }

    // MARK: Recovery

    @Test func recoveryHrvSquareAndBodyBatteryTileSayNeedsTheHubOnDevice() {
        let layout = recoveryTileLayout(orderRaw: "", hiddenRaw: "")
        let items = recoveryTileItems(days: offDays, layout: layout, editing: false, now: offNow, capabilities: Self.onDevice)
        let hrv = items.first { $0.id == "hrv" }
        #expect(hrv?.value == nil && hrv?.status == .missing(.needsHub))
        #expect(items.first { $0.id == "rhr" }?.value == 52)
        let battery = recoveryWatchReadings(days: offDays, today: "2026-10-07", capabilities: Self.onDevice).first { $0.id == "bodyBattery" }
        #expect(battery?.value == "—" && battery?.caption == JIMissingReason.needsHub.rawValue)
    }

    @Test func recoveryHubOnlyTilesShowTheRealValueUnderTheHub() {
        let layout = recoveryTileLayout(orderRaw: "", hiddenRaw: "")
        let items = recoveryTileItems(days: offDays, layout: layout, editing: false, now: offNow, capabilities: .hubAll)
        #expect(items.first { $0.id == "hrv" }?.value == 42)
        let battery = recoveryWatchReadings(days: offDays, today: "2026-10-07", capabilities: .hubAll).first { $0.id == "bodyBattery" }
        #expect(battery?.value == "18–88")
    }

    // MARK: sim-rendered proof shots (OFF2_SHOTS → TEST_RUNNER_OFF2_SHOTS)

    func render<V: View>(_ name: String, _ view: V, height: CGFloat) -> Bool {
        let r = ImageRenderer(content: view.jiTheme(.native).environment(\.jiOffscreenRender, true)
            .frame(width: 402, height: height).background(Color(white: 0.95)))
        r.scale = 3
        guard let img = r.uiImage, let png = img.pngData() else { return false }
        if let dir = ProcessInfo.processInfo.environment["OFF2_SHOTS"], !dir.isEmpty {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        return true
    }

    @Test func renderTodayAndRecoveryTilesOnDeviceAndHub() async throws {
        for (name, caps) in [("ondevice", Self.onDevice), ("hub", DataCapability.hubAll)] {
            let model = TodayViewModel(provider: OffStub(capabilities: caps), cache: OfflineCache(db: try AppDatabase.inMemory()),
                                       now: { offNow })
            await model.load()
            let chips = model.gridChips.filter { ["hrv", "rhr", "body_battery", "readiness"].contains($0.id) }
            let today = LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(chips) { chip in
                    let spec = todaySummaryCardSpec(for: chip)
                    SummaryCard(icon: spec.icon, tint: .blue, title: spec.title, value: spec.value, unit: spec.unit,
                                timestamp: spec.timestamp, sparkline: spec.sparkline, sourceMissing: spec.sourceMissing,
                                missingCopy: spec.missingCopy)
                }
            }.padding(16)
            #expect(render("off2-today-tiles-\(name)", today, height: 420))
            let items = recoveryTileItems(days: offDays, layout: recoveryTileLayout(orderRaw: "", hiddenRaw: ""), editing: false,
                                          now: offNow, capabilities: caps)
            let battery = recoveryWatchReadings(days: offDays, today: "2026-10-07", capabilities: caps).first { $0.id == "bodyBattery" }
            let recovery = VStack(alignment: .leading, spacing: 12) {
                SquareGrid(items: items, columns: recoveryGridColumns, family: .tile)
                Text("Body Battery: \(battery?.value ?? "") · \(battery?.caption ?? "")").font(.footnote)
            }.padding(16)
            #expect(render("off2-recovery-tiles-\(name)", recovery, height: 460))
        }
    }
}
