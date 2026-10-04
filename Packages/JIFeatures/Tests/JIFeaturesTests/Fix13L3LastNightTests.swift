import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W-FIX13 F-7 (B-69) — the Today vitals tile (HRV, RHR, as-of) and the readiness ring show the
/// hub's `last_night` (`/vitals/recovery`): the newest night, Apple (dso 4) before Garmin (dso 2).
nonisolated struct Fix13LastNightStub: HealthDataProvider, RecoveryLastNightProviding {
    let capabilities: DataCapability = .hubAll
    let inner = MockDataProvider()
    var days: [RecoveryDay]
    var night: RecoveryLastNight?
    func health() async throws -> HealthResponse { try await inner.health() }
    func gate(windowDays: Int) async throws -> GateResponse { try await inner.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try await inner.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await inner.morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { days }
    func syncStatus() async throws -> SyncStatus { SyncStatus(lastSync: nil) }
    func recoveryLastNight() async throws -> RecoveryLastNight? { night }
}

@MainActor @Suite struct Fix13L3LastNightTests {
    /// 2026-10-04 07:30 in Zurich.
    static let now = ISO8601DateFormatter().date(from: "2026-10-04T05:30:00Z")!
    static let zurich = TimeZone(identifier: "Europe/Zurich")!
    /// The Garmin rows `days[]` carries: its newest night is 10-03 (readiness 94).
    static let garminDays = [
        RecoveryDay(date: "2026-10-03", rhrBpm: 62, readinessScore: 94, hrvRmssdMs: 39),
        RecoveryDay(date: "2026-10-02", rhrBpm: 61, readinessScore: 90, hrvRmssdMs: 41),
    ]
    static let apple = RecoveryLastNight(date: "2026-10-04", source: "apple", dsoKey: 4, hrvMs: 31.5, rhrBpm: 58,
                                         readiness: 77, readinessStatus: "ok")

    func vm(_ provider: any HealthDataProvider) throws -> TodayViewModel {
        TodayViewModel(provider: provider, cache: OfflineCache(db: try AppDatabase.inMemory()),
                       now: { Self.now }, uploadRecord: nil, zone: { Self.zurich })
    }

    @Test func decodesLastNightFromTheRecoveryReport() throws {
        let json = """
        {"days": [], "last_night": {"date": "2026-10-04", "source": "apple", "dso_key": 4, "hrv_ms": 31.5,
         "rhr_bpm": 58.0, "readiness": 77, "readiness_status": "ok"}}
        """
        let report = try JSON.decoder.decode(RecoveryReport.self, from: Data(json.utf8))
        #expect(report.lastNight == Self.apple)
        let older = try JSON.decoder.decode(RecoveryReport.self, from: Data(#"{"days": []}"#.utf8))
        #expect(older.lastNight == nil)
    }

    @Test func tileAndRingShowAppleTonightAsOfToday() async throws {
        let model = try vm(Fix13LastNightStub(days: Self.garminDays, night: Self.apple))
        await model.load()
        let hrv = try #require(model.chips.first { $0.id == "hrv" })
        let rhr = try #require(model.chips.first { $0.id == "rhr" })
        #expect(hrv.value == 31.5 && rhr.value == 58)
        #expect(hrv.asOf == nil && rhr.asOf == nil)    // nil = today: no "as of Oct 3"
        #expect(model.readiness == 77)
        #expect(model.squareChips.first { $0.id == "readiness" }?.value == 77)
    }

    @Test func calibratingAppleNightNeverBorrowsGarminsReadiness() async throws {
        var night = Self.apple
        night.readiness = nil; night.readinessStatus = "calibrating"
        let model = try vm(Fix13LastNightStub(days: Self.garminDays, night: night))
        await model.load()
        #expect(model.readiness == nil)
        #expect(model.chips.first { $0.id == "hrv" }?.value == 31.5)
    }

    @Test func garminNightKeepsItsOwnDateInTheAsOf() async throws {
        let garmin = RecoveryLastNight(date: "2026-10-03", source: "garmin", dsoKey: 2, hrvMs: 39, rhrBpm: 62, readiness: 94, readinessStatus: "ok")
        let model = try vm(Fix13LastNightStub(days: Self.garminDays, night: garmin))
        await model.load()
        let hrv = try #require(model.chips.first { $0.id == "hrv" })
        #expect(hrv.value == 39)
        #expect(hrv.asOf == kpiAsOfLabel(valueDate: "2026-10-03", today: "2026-10-04"))
        #expect(model.readiness == 94)
    }

    @Test func aHubWithoutLastNightKeepsTheRowsPath() async throws {
        let model = try vm(Fix13LastNightStub(days: Self.garminDays, night: nil))
        await model.load()
        #expect(model.chips.first { $0.id == "hrv" }?.value == 39)
        #expect(model.readiness == 94)
    }
}
