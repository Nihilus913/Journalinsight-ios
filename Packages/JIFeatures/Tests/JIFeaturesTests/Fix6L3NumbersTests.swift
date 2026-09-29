import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

// W-FIX6 L3 "Numbers + labels": F6-1, F6-3, F6-4, F6-8, F6-9 (docs/audits/2026-09-25-regression-bugs.md).

// MARK: - F6-1 Recovery Sleep card normal = KPI detail / hub normal

/// Serves `windowDays` nights ending today, like `/vitals/recovery?window_days=`.
nonisolated struct Fix6L3RecoveryWindowProvider: HealthDataProvider {
    let capabilities: DataCapability = .hubAll
    let inner = MockDataProvider()
    let all: [RecoveryDay]
    func health() async throws -> HealthResponse { try await inner.health() }
    func gate(windowDays: Int) async throws -> GateResponse { try await inner.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try await inner.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await inner.morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { Array(all.sorted { $0.date < $1.date }.suffix(windowDays)) }
    func syncStatus() async throws -> SyncStatus { try await inner.syncStatus() }
}

@Test @MainActor func f6_1SleepCardNormalMatchesTheDetailNormal() async throws {
    let today = RecoveryInsightService.localDayKey(Date())
    // 60 nights with a rising score, so a truncated window gives a different band.
    let all: [RecoveryDay] = try (0..<60).map { i in
        RecoveryDay(date: try CalendarMath.addDays(today, i - 59), sleepScore: 60 + Double(i) * 0.6,
                    sleepDurationSec: 26_000, rhrBpm: 55, acwr: nil, hrvWeeklyAvg: 45)
    }
    let model = RecoveryViewModel(provider: Fix6L3RecoveryWindowProvider(all: all), cache: OfflineCache(db: try AppDatabase.inMemory()))
    await model.load()
    // The KPI detail reads a long window; the normal (today−34 … today−7) is the same 28 nights.
    let detail = KpiNormal.make(points: all.map { (date: $0.date, value: $0.sleepScore) }, today: today).normal
    let card = recoveryCardNormal(metric: .sleep, days: model.days, insightNormal: nil, today: today)
    #expect(detail != nil)
    #expect(card == detail)
}

// MARK: - F6-3 KPI detail table words are true

@Test func f6_3TableWordsDoNotClaimTheGateOrMiddleFifty() {
    let nights = (1...20).map { (date: String(format: "2026-09-%02d", $0), value: Optional(Double(150 + $0))) }
    let rows = kpiDetailTableRows(history: nights, value: 163, unit: "min", decimals: 0, isNightly: false)
    #expect(!rows[1].subtitle.contains("gate"))
    #expect(rows[0].subtitle == "total of the 7 days to yesterday")
    #expect(rows[1].subtitle == "mean of the last 7 weekly totals")
    #expect(!rows[2].subtitle.contains("50 %"))
    #expect(rows[2].subtitle.contains("median"))
    let nightly = kpiDetailTableRows(history: nights, value: 30, unit: "ms", decimals: 0)
    #expect(nightly[1].subtitle == "mean of the last 7 nights")
    let daily = kpiDetailTableRows(history: nights, value: 80, unit: "kg", decimals: 1, isNightly: false)
    #expect(daily[1].subtitle == "mean of the last 7 days")
    #expect(daily[0].subtitle == "the newest reading")
}

// MARK: - F6-4 Goals "pending" / "Couldn't save" clear live after the foreground drain

/// Goals read that fails until `up` (lock-guarded: `goals()` is nonisolated).
final class Fix6L3GoalsHub: GoalsSetupProviding, @unchecked Sendable { // test-only
    let inner = MockDataProvider()
    private let lock = NSLock()
    private var _up = false
    var up: Bool { get { lock.withLock { _up } } set { lock.withLock { _up = newValue } } }
    func energy(windowDays: Int) async throws -> EnergyReport { try await inner.energy(windowDays: windowDays) }
    func goals() async throws -> Goals {
        guard up else { throw HubError.network("down") }
        return try await inner.goals()
    }
}

@MainActor final class Fix6L3PendingBox { var pending = false }

/// W-FIX10 F10-1: a save is local now (no failed weight/steps patch to re-send); what clears live
/// once the drain delivered is the pending line and a load-time hub error.
@Test @MainActor func f6_4PendingAndLoadErrorClearOnceTheDrainDelivered() async throws {
    let hub = Fix6L3GoalsHub()
    let box = Fix6L3PendingBox()
    let vm = GoalsSetupViewModel(provider: hub, hubPendingSource: { box.pending }, hubPollInterval: .milliseconds(5))
    await vm.load()
    guard case .error = vm.phase else { Issue.record("expected the load error"); return }
    box.pending = true                 // a targets body is queued
    vm.refreshHubPending()             // scene .active: runs BEFORE the drain finished
    #expect(vm.hubPending)
    hub.up = true; box.pending = false // the foreground drain delivered
    await vm.hubWatch?.value
    #expect(!vm.hubPending)
    #expect(vm.phase == .loaded)       // no stale "Hub offline" left over
    #expect(vm.goals != nil)
}

@Test @MainActor func f6_4WatcherStopsWhileStillPendingAfterItsBudget() async throws {
    let box = Fix6L3PendingBox(); box.pending = true
    let vm = GoalsSetupViewModel(provider: GoalsFakeProvider(), hubPendingSource: { box.pending },
                                 hubPollInterval: .milliseconds(1), hubPollLimit: 3)
    vm.refreshHubPending()
    await vm.hubWatch?.value
    #expect(vm.hubPending)             // still queued: stays honest
}

// MARK: - F6-8 / F6-9 Trends Load + Weight show values (dated)

private func dailyRows(_ json: String) throws -> [DailyKpiRow] {
    try JSON.decoder.decode([DailyKpiRow].self, from: Data(json.utf8))
}

@Test func f6_8TrendsLoadIsTheGateInputLoad() throws {
    let load = RecoveryLoadReading(minutes: 163, normal: nil, points: [20, 30, nil, 25, 40, 18, 30])
    let cards = trendsCards(recovery: [], daily: [], averages: nil, today: "2026-09-28", load: load)
    let card = try #require(cards.first { $0.id == "load" })
    #expect(card.value == 163)
    #expect(card.unit == "min")
    #expect(card.decimals == 0)
    #expect(card.status == .missing(.calibrating))
}

@Test func f6_8TrendsLoadWithoutAnyLoadStaysNoData() throws {
    let cards = trendsCards(recovery: [], daily: [], averages: nil, today: "2026-09-28")
    #expect(cards.first { $0.id == "load" }?.value == nil)
}

@Test func f6_9TrendsWeightShowsTheLastWeighInWithItsDate() throws {
    let daily = try dailyRows("""
    [{"date":"2026-09-19","weight_kg":79.5},{"date":"2026-09-22","weight_kg":null},
     {"date":"2026-09-24","weight_kg":null},{"date":"2026-09-26","weight_kg":null},
     {"date":"2026-09-27","weight_kg":null},{"date":"2026-09-28","weight_kg":null},
     {"date":"2026-09-25","weight_kg":null},{"date":"2026-09-23","weight_kg":null}]
    """)
    let cards = trendsCards(recovery: [], daily: daily, averages: nil, today: "2026-09-28")
    let weight = try #require(cards.first { $0.id == "weight" })
    #expect(weight.value == 79.5)
    #expect(weight.asOf == kpiAsOfLabel(valueDate: "2026-09-19", today: "2026-09-28"))
    #expect(weight.asOf != nil)
    // A week that has weigh-ins keeps the 7-day mean and no date.
    let fresh = try dailyRows(#"[{"date":"2026-09-27","weight_kg":80.0},{"date":"2026-09-28","weight_kg":79.0}]"#)
    let w2 = try #require(trendsCards(recovery: [], daily: fresh, averages: nil, today: "2026-09-28").first { $0.id == "weight" })
    #expect(w2.value == 79.5 && w2.asOf == nil)
}
