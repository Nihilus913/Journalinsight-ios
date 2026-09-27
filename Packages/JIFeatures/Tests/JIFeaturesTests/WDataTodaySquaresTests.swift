import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W-DATA R8 (DEV-09 data half): on the hub source, every Today square equals what the hub's
/// routes serve for the same day. Live GETs 2026-09-27 (`/planning/gate?window_days=4` trimmed,
/// `/vitals/recovery`): HRV 23.72 (RMSSD), RHR 71, sleep 84, steps 5959 — all today's, no "as of";
/// food is 09-24's (YAZIO's last real day) and says so.
nonisolated struct WDataHubStub: HealthDataProvider {
    let capabilities: DataCapability = .hubAll
    let inner = MockDataProvider()
    static let gateJSON = #"""
    {"averages":{"avg_kcal":1183.1,"avg_protein_g":98.3,"avg_rhr":76.5,"avg_sleep_score":83.0,"acwr":0.0,"trends":{}},
     "daily":[{"date":"2026-09-27","kcal_consumed":null,"kcal_goal":1935.0,"protein_g":null,"rhr_bpm":71,"steps":5959,"weight_kg":null},
              {"date":"2026-09-26","kcal_consumed":null,"kcal_goal":1935.0,"protein_g":null,"rhr_bpm":73,"steps":16485,"weight_kg":null},
              {"date":"2026-09-25","kcal_consumed":null,"kcal_goal":1935.0,"protein_g":null,"rhr_bpm":80,"steps":11082,"weight_kg":null},
              {"date":"2026-09-24","kcal_consumed":1183.1,"kcal_goal":1935.0,"protein_g":98.3,"rhr_bpm":82,"steps":10045,"weight_kg":null}],
     "recommendation":"INSUFFICIENT_DATA","triggered_rules":[],"suggestions":[],"tracked_days":0,"total_days":4,"min_tracked_days":4}
    """#
    static let days: [RecoveryDay] = [
        RecoveryDay(date: "2026-09-27", sleepScore: 84, sleepDurationSec: 24814, rhrBpm: 71, acwr: 0, hrvWeeklyAvg: 39, hrvRmssdMs: 23.72),
        RecoveryDay(date: "2026-09-26", sleepScore: 80, sleepDurationSec: 25352, rhrBpm: 73, acwr: 0, hrvWeeklyAvg: 34, hrvRmssdMs: 24.21),
        RecoveryDay(date: "2026-09-25", sleepScore: 89, sleepDurationSec: 30895, rhrBpm: 80, acwr: 0, hrvWeeklyAvg: 25, hrvRmssdMs: 20.68),
    ]
    func health() async throws -> HealthResponse { try await inner.health() }
    func gate(windowDays: Int) async throws -> GateResponse { try JSON.decoder.decode(GateResponse.self, from: Data(Self.gateJSON.utf8)) }
    func morning() async throws -> MorningResponse { try await inner.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await inner.morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { Self.days }
    func syncStatus() async throws -> SyncStatus { throw HubError.network("simulated") }
}

@MainActor
struct WDataTodaySquaresTests {
    /// 2026-09-27 12:26 UTC (14:26 CEST, the live GET).
    static let now = ISO8601DateFormatter().date(from: "2026-09-27T12:26:00Z")!

    @Test func hubSquaresEqualTheHubRoutesForTheSameDay() async throws {
        let model = TodayViewModel(provider: WDataHubStub(), cache: OfflineCache(db: try AppDatabase.inMemory()), now: { Self.now })
        await model.load()
        let byId = Dictionary(uniqueKeysWithValues: model.gridChips.map { ($0.id, $0) })
        // Last night's recovery values are today's rows — no "as of".
        #expect(byId["hrv"]?.value == 23.72 && byId["hrv"]?.asOf == nil)
        #expect(byId["rhr"]?.value == 71 && byId["rhr"]?.asOf == nil)
        #expect(byId["sleep"]?.value == 84 && byId["sleep"]?.asOf == nil)
        #expect(byId["steps"]?.value == 5959 && byId["steps"]?.asOf == nil)
        // Food is YAZIO's last real day, named by its own date (DEV-11).
        let sep24 = kpiAsOfLabel(valueDate: "2026-09-24", today: "2026-09-27")
        #expect(byId["kcal"]?.value == 1183.1 && byId["kcal"]?.asOf == sep24)
        #expect(byId["protein"]?.value == 98.3 && byId["protein"]?.asOf == sep24)
        // The hub's invented ACWR 0.0 is "—", never a 0 (BUG-12).
        #expect(byId["acwr"]?.value == nil)
    }
}
