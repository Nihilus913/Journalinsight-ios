import Foundation
import Testing
import JICore
import JICompute
import JIDesign
import JIPersistence
@testable import JIFeatures

/// W-FIX5 L1 (WD-1/2/3): the gate-input Load (7-day minutes + band, `recoveryLoadReading`) is the
/// one Load the Today square, the KPI detail, My KPIs and the Rationale row show while no current
/// ACWR exists. A current ACWR keeps its place everywhere.

/// A hub-like provider: recovery rows carry no ACWR (Apple never sends one) and it serves
/// `/vitals/recovery-inputs` (the mock's deterministic 42 days).
private nonisolated struct Fix5LoadProvider: HealthDataProvider, NutritionProviding, KpiTargetsProviding, RecoveryInputsProviding {
    let capabilities: DataCapability = .hubAll
    let inner = MockDataProvider()
    func health() async throws -> HealthResponse { try await inner.health() }
    func gate(windowDays: Int) async throws -> GateResponse { try await inner.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try await inner.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await inner.morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] {
        try await inner.recovery(windowDays: windowDays).map { var d = $0; d.acwr = 0.12; return d }   // stale (Sep) ratio
    }
    func syncStatus() async throws -> SyncStatus { try await inner.syncStatus() }
    func nutritionDay(date: String) async throws -> NutritionDayDetail? { try await inner.nutritionDay(date: date) }
    func nutritionWeek(windowDays: Int) async throws -> [NutritionDailyRow] { try await inner.nutritionWeek(windowDays: windowDays) }
    func kpiTargets() async throws -> [KpiTarget] { try await inner.kpiTargets() }
    func recoveryInputs(date: String, windowDays: Int) async throws -> [RecoveryInputDay] {
        MockDataProvider.recoveryInputDays(date: date, windowDays: windowDays)
    }
}

private let fix5Today = RecoveryInsightService.localDayKey(Date())
private var fix5Expected: RecoveryLoadReading {
    recoveryLoadReading(days: MockDataProvider.recoveryInputDays(date: fix5Today, windowDays: 42),
                        today: fix5Today)!
}

@MainActor
private func fix5Detail(_ provider: some HealthDataProvider & NutritionProviding & KpiTargetsProviding) throws -> KpiDetailViewModel {
    KpiDetailViewModel(metric: .acwr, healthProvider: provider, nutritionProvider: provider, targetsProvider: provider,
                       cache: OfflineCache(db: try AppDatabase.inMemory()))
}

// MARK: WD-1 — the Load square opens a detail with the same 7-day minutes + band

@Test @MainActor func wd1_loadDetailShowsTheGateInputMinutesNotAStaleAcwr() async throws {
    let vm = try fix5Detail(Fix5LoadProvider())
    await vm.load()
    let expected = fix5Expected
    #expect(vm.showsLoadMinutes)
    #expect(vm.value == expected.minutes)
    #expect(vm.def.unit == "min")
    #expect(vm.def.decimals == 0)
    #expect(!vm.def.label.contains("ACWR"))
    #expect(vm.asOfLabel == nil)                    // never "as of 10 Sep"
    #expect(vm.target == nil)                       // the ACWR rule's ratio editor does not apply to minutes
    // The chart plots 7-day loads; its newest point is the headline, and its band is the tile's.
    #expect(vm.history.last?.value == expected.minutes)
    let normal = KpiNormal.make(points: vm.history, today: fix5Today).normal
    #expect(normal == expected.normal)
    #expect(vm.loadReading == expected)
}

@Test @MainActor func wd1_providerWithoutRecoveryInputsKeepsTheAcwrScreen() async throws {
    let vm = try fix5Detail(KpiFakeProvider())
    await vm.load()
    #expect(!vm.showsLoadMinutes)
    #expect(vm.def.label == "Training load (ACWR)")
    #expect(vm.def.decimals == 2)
}

@Test func wd1_loadHistoryIsTheRolling7DayLoadEndingYesterday() throws {
    let days = MockDataProvider.recoveryInputDays(date: "2026-09-24", windowDays: 42)
    let h = kpiLoadHistory(days: days, today: "2026-09-24")
    #expect(h.last?.date == "2026-09-23")
    #expect(h.last?.value == recoveryLoadReading(days: days, today: "2026-09-24")?.minutes)
    #expect(h.allSatisfy { $0.value.map { $0 >= 0 } ?? true })
    #expect(kpiLoadHistory(days: [], today: "2026-09-24").isEmpty)
}

// MARK: WD-2 — My KPIs Load square has the value

@Test func wd2_catalogueLoadSquareCarriesTheMinutesWhenNoAcwr() throws {
    let load = recoveryLoadReading(days: MockDataProvider.recoveryInputDays(date: "2026-09-24", windowDays: 42), today: "2026-09-24")!
    let items = kpiCatalogueItems(group: .recovery, visible: [], value: { _ in nil }, today: "2026-09-24",
                                  goalCaption: { _, _ in nil }, load: load)
    let sq = try #require(items.first { $0.id == "acwr" })
    #expect(sq.value == load.minutes.rounded())
    #expect(sq.unit == "min")
    #expect(sq.decimals == 0)
    #expect(sq.goalText == load.caption)
    #expect(!sq.label.contains("ACWR"))
    #expect(sq.status == nil)
    // Other squares are unchanged; a missing one still says No data.
    #expect(items.first { $0.id == "hrv" }?.status == .missing(.noData))
}

@Test func wd2_aCurrentAcwrKeepsTheSquare() throws {
    let load = recoveryLoadReading(days: MockDataProvider.recoveryInputDays(date: "2026-09-24", windowDays: 42), today: "2026-09-24")!
    let items = kpiCatalogueItems(group: .recovery, visible: [], value: { $0 == .acwr ? KpiReading(value: 1.04, date: "2026-09-24") : nil },
                                  today: "2026-09-24", goalCaption: { _, _ in nil }, load: load)
    let sq = try #require(items.first { $0.id == "acwr" })
    #expect(sq.value == 1.04)
    #expect(sq.decimals == 2)
    let none = kpiCatalogueItems(group: .recovery, visible: [], value: { _ in nil }, today: "2026-09-24",
                                 goalCaption: { _, _ in nil }, load: nil)
    #expect(none.first { $0.id == "acwr" }?.status == .missing(.noData))
}

// MARK: WD-3 — Rationale Load row reads the gate-input load

@Test func wd3_rationaleLoadRowUsesTheMinutesWhenNoAcwr() throws {
    let load = recoveryLoadReading(days: MockDataProvider.recoveryInputDays(date: "2026-09-24", windowDays: 42), today: "2026-09-24")!
    let row = try #require(gateRationaleCountedRows(signals: [], normals: [:], load: nil, loadReading: load).last)
    #expect(row.id == "load")
    #expect(row.value == load.minutes)
    #expect(row.unit == "min")
    #expect(row.decimals == 0)
    #expect(row.status == .contextOnly)
    #expect(!row.sentence.contains("No current load reading"))
    #expect(row.sentence.contains("7 days"))
}

@Test func wd3_acwrStillWinsAndNoReadingStillSaysLeftOut() throws {
    let load = recoveryLoadReading(days: MockDataProvider.recoveryInputDays(date: "2026-09-24", windowDays: 42), today: "2026-09-24")!
    let acwr = try #require(gateRationaleCountedRows(signals: [], normals: [:], load: 1.04, loadReading: load).last)
    #expect(acwr.value == 1.04)
    #expect(acwr.decimals == 2)
    let none = try #require(gateRationaleCountedRows(signals: [], normals: [:], load: nil, loadReading: nil).last)
    #expect(none.value == nil)
    #expect(none.sentence == "No current load reading. Left out.")
}
