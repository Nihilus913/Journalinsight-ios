import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

/// W-FIX6 lane L1 — "One verdict" (F6-11 S1, F6-2, F6-7). Rows: HealthTraining
/// `docs/audits/2026-09-25-regression-bugs.md`. The 2026-09-28 payload is the prod hub's
/// `/planning/morning` after morning_go 05:27 (`fix6Morning20260928JSON`).
///
/// Root cause of F6-11 (proven from the hub's api.log): the phone never GET `/planning/morning`
/// after 2026-09-24 — the debug "read from watch" data source was on, `HealthKitProvider.morning()`
/// throws `notCapable(.gate)`, and `SectionLoader` fell back to the 09-24 cache ("GO
/// (auto-regulated) — Long Zone 2 75-90min"), which Decide, the widget and the Live Activity all
/// showed as today's call. The verdict is the hub's alone: it must be read from the hub whatever
/// data source the tiles use.

private func decodeMorning(_ json: String) throws -> MorningResponse {
    try JSON.decoder.decode(MorningResponse.self, from: Data(json.utf8))
}

/// 2026-09-28T05:32:00+02:00 — the moment of Toby's screenshots.
private let morningOf0928 = Date(timeIntervalSince1970: 1_790_566_320)

/// What the on-device data source (T2, `HealthKitProvider`) answers for the hub-only routes.
private struct OnDeviceOnlyProvider: HealthDataProvider {
    var capabilities: DataCapability { [.recovery, .sync] }
    func health() async throws -> HealthResponse { HealthResponse(status: "ok") }
    func gate(windowDays: Int) async throws -> GateResponse { throw HubError.decoding("not capable: gate") }
    func morning() async throws -> MorningResponse { throw HubError.decoding("not capable: gate") }
    func morningVerdict(date: String) async throws -> MorningVerdict { throw HubError.decoding("not capable: gate") }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { [] }
    func syncStatus() async throws -> SyncStatus { SyncStatus(lastSync: nil) }
}

/// The hub, serving the saved 2026-09-28 `/planning/morning`.
private struct Hub0928: HealthDataProvider {
    var capabilities: DataCapability { .hubAll }
    func health() async throws -> HealthResponse { HealthResponse(status: "ok") }
    func gate(windowDays: Int) async throws -> GateResponse { try await MockDataProvider().gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try decodeMorning(fix6Morning20260928JSON) }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await MockDataProvider().morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { [] }
    func syncStatus() async throws -> SyncStatus { SyncStatus(lastSync: nil) }
}

/// The 09-24 call the phone had cached (hub `/planning/morning-verdict?date=2026-09-24`).
private let cached0924 = """
{"today_activities":[],"verdict":"GO (auto-regulated) — Long Zone 2 75-90min","verdict_date":"2026-09-24","carb_watch_floor":120,"hrv_series":[]}
"""

@MainActor
struct Fix6L1OneVerdictTests {
    // MARK: F6-11 — the saved payload is what the hub said

    @Test func the0928PayloadDecodesToTheHubsCall() throws {
        let m = try decodeMorning(fix6Morning20260928JSON)
        #expect(m.verdict == "GO (auto-regulated) — Day 1 Full Upper + Z2 40min")
        #expect(m.verdictDate == "2026-09-28")
        let byKey = Dictionary(uniqueKeysWithValues: (m.gateSignals ?? []).map { ($0.key, $0) })
        #expect(byKey["hrv"]?.value == 23 && byKey["hrv"]?.status == .amber)
        #expect(byKey["sleep_h"]?.value == 8.2)
        #expect(byKey["recovery"]?.value == 36 && byKey["recovery"]?.status == .pass)
    }

    // MARK: F6-11 root cause — the verdict comes from the hub even when the tiles read the watch

    @Test func onDeviceDataSourceStillShowsTheHubsCall() async throws {
        let cache = OfflineCache(db: try AppDatabase.inMemory())
        let model = TodayViewModel(provider: OnDeviceOnlyProvider(), verdictProvider: Hub0928(), cache: cache,
                                   now: { morningOf0928 }, uploadRecord: nil)
        await model.load()
        #expect(model.morning?.verdict == "GO (auto-regulated) — Day 1 Full Upper + Z2 40min")
        #expect(model.verdictDate == "2026-09-28")
    }

    @Test func aStaleCachedCallIsReplacedByTheHubsCall() async throws {
        let cache = OfflineCache(db: try AppDatabase.inMemory())
        try cache.put("today.morning", try decodeMorning(cached0924))
        let model = TodayViewModel(provider: OnDeviceOnlyProvider(), verdictProvider: Hub0928(), cache: cache,
                                   now: { morningOf0928 }, uploadRecord: nil)
        await model.load()
        #expect(model.verdict.session == "Day 1 Full Upper + Z2 40min")
    }

    @Test func withoutAVerdictProviderTheDataSourceIsAsked() async throws {
        let cache = OfflineCache(db: try AppDatabase.inMemory())
        let model = TodayViewModel(provider: Hub0928(), cache: cache, now: { morningOf0928 }, uploadRecord: nil)
        await model.load()
        #expect(model.verdictDate == "2026-09-28")
    }

    // MARK: F6-11 — ONE headline for Decide, Day, widgets and the Live Activity

    @Test func theHeadlineIsDecidesWordsForTheAmberDay() throws {
        let parts = verdictParts(try decodeMorning(fix6Morning20260928JSON).verdict)
        let h = verdictHeadline(parts: parts, override: nil)
        #expect(h.word == decideWord(effectiveVerdictParts(parts: parts, override: nil)))
        #expect(h.word == "Modified")
        #expect(h.session == "Day 1 Full Upper + Z2 40min")
        #expect(h.tone == .amber)
    }

    @Test func theHeadlineFollowsTheUsersOverride() {
        let parts = verdictParts("GO (auto-regulated) — Day 1 Full Upper + Z2 40min")
        let o = VerdictOverride(date: "2026-09-28", choice: .rest, reason: nil, session: "Rest — walks only")
        let h = verdictHeadline(parts: parts, override: o)
        #expect(h.word == "Rest")
        #expect(h.session == "Rest — walks only")
        #expect(h.tone == .muted)
    }

    @Test func noVerdictIsADashWithItsReason() {
        let h = verdictHeadline(parts: verdictParts(nil), override: nil)
        #expect(h.word == "—")
        #expect(h.session == "No verdict yet")
    }

    @Test func aCallFromAnotherDayIsNeverHeadedAsToday() {
        #expect(decideCallHeader(verdictDate: "2026-09-28", isStale: false, today: "2026-09-28") == "YOUR CALL FOR TODAY")
        #expect(decideCallHeader(verdictDate: "2026-09-24", isStale: false, today: "2026-09-28") == "LAST CALL · THU, SEP 24")
        #expect(decideCallHeader(verdictDate: "2026-09-27", isStale: true, today: "2026-09-28") == "LAST CALL · SUN, SEP 27")
        #expect(decideCallHeader(verdictDate: nil, isStale: nil, today: "2026-09-28") == "YOUR CALL FOR TODAY")
    }

    // MARK: F6-11 — ring copy

    @Test func ringNeverSaysNOfNCalibrating() {
        let readiness = decideReadinessCaption(score: nil, nights: 7)
        #expect(!readiness.contains("7 of 7"))
        #expect(readiness.contains("—") || readiness.contains("No data") || readiness.contains("Calibrating"))
        let full = RecoveryScoreResult(status: .calibrating, score: nil, raw: nil, components: [], nights: 20, nightsNeeded: 14)
        let caption = decideReadinessCaption(score: nil, nights: nil, recovery: full)
        #expect(!caption.contains("14 of 14"))
        #expect(!caption.contains(" of "))
        // Below the need the count stays (it is true and useful).
        let partial = RecoveryScoreResult(status: .calibrating, score: nil, raw: nil, components: [], nights: 9, nightsNeeded: 14)
        #expect(decideReadinessCaption(score: nil, nights: nil, recovery: partial).contains("9 of 14"))
        #expect(decideReadinessCaption(score: nil, nights: 3).contains("3 of 7"))
    }

    @Test func ringShowsTheHubsRecoveryScore() throws {
        let signals = try decodeMorning(fix6Morning20260928JSON).gateSignals
        let hub = decideHubRecovery(signals)
        #expect(hub == 36)
        #expect(decideRingScore(readiness: nil, recovery: nil, hubRecovery: hub) == 36)
        #expect(decideReadinessCaption(score: 36, nights: nil, recovery: nil, hubRecovery: hub) == "Recovery")
        #expect(decideReadinessCaption(score: 20, nights: nil, recovery: nil, hubRecovery: 20) == "Recovery low")
        // Garmin readiness still wins when the hub sends it.
        #expect(decideRingScore(readiness: 70, recovery: nil, hubRecovery: hub) == 70)
        #expect(decideHubRecovery(nil) == nil)
    }

    // MARK: F6-7 — the Fuel goal line reads the same goal as Goals

    @Test func fuelGoalIsTheUsersGoalNotTheRowsSeed() throws {
        let json = #"[{"date":"2026-09-27","kcal_consumed":1748,"kcal_goal":2500,"protein_g":150}]"#
        let rows = try JSON.decoder.decode([DailyKpiRow].self, from: Data(json.utf8))
        let unset = dayFuel(daily: rows, today: "2026-09-28", kcalGoal: nil)
        #expect(unset.kcalGoal == nil)
        #expect(dayFuelLeftText(kcal: unset.kcal, goal: unset.kcalGoal, isToday: false) == nil)
        let set = dayFuel(daily: rows, today: "2026-09-28", kcalGoal: 2100)
        #expect(set.kcalGoal == 2100)
        #expect(dayFuelLeftText(kcal: set.kcal, goal: set.kcalGoal, isToday: false) == "352 under your goal")
    }
}
