import SwiftUI
import Testing
import JICore
import JICompute
import JIDesign
import JIPersistence
@testable import JIFeatures

// W-B57-W3 fixer — verifier failures (Decide ring, normals, captions, windows).

// Decide-ring: with a recovery score the ring shows it, never "7 of 7 so far · Calibrating".
@Test func decideRingShowsTheRecoveryScoreWhenTheHubHasNoReadiness() {
    let scored = RecoveryScoreResult(status: .ok, score: 5, raw: -2, components: [], nights: 22)
    #expect(decideRingScore(readiness: nil, recovery: scored) == 5)
    #expect(decideReadinessCaption(score: 5, nights: 7, recovery: scored) == "Recovery low")
    let fine = RecoveryScoreResult(status: .ok, score: 61, raw: 0.2, components: [], nights: 22)
    #expect(decideReadinessCaption(score: 61, nights: 7, recovery: fine) == "Recovery")
    // Garmin readiness wins when the hub has it.
    #expect(decideRingScore(readiness: 72, recovery: scored) == 72)
    #expect(decideReadinessCaption(score: 72, nights: 7, recovery: scored) == "Readiness")
}

@Test func decideRingCalibratingAndMissingUseTheRecoveryNights() {
    let cal = RecoveryScoreResult(status: .calibrating, score: nil, raw: nil, components: [], nights: 9)
    #expect(decideRingScore(readiness: nil, recovery: cal) == nil)
    #expect(decideReadinessCaption(score: nil, nights: 7, recovery: cal)
            == "Recovery needs 14 nights · 9 of 14 so far · Calibrating")
    let miss = RecoveryScoreResult(status: .missing, score: nil, raw: nil, components: [], nights: 22)
    #expect(decideReadinessCaption(score: nil, nights: 7, recovery: miss) == "Recovery · No data")
    // No insight at all keeps the readiness wording.
    #expect(decideReadinessCaption(score: nil, nights: 3, recovery: nil)
            == "Readiness needs 7 overnight nights · 3 of 7 so far · Calibrating")
}

private func fxSignal(_ key: String, _ label: String, value: Double?, status: GateSignalStatus, note: String? = nil) -> GateSignal {
    GateSignal(key: key, label: label, value: value, unit: "ms", threshold: 0,
               direction: .min, scaleMin: 0, scaleMax: 120, status: status, note: note)
}

// signal-normals: the Apple "HRV (7-day)" row takes the recovery score's 28-night normal (the same
// 7-day-mean-vs-normal comparison the score makes) when the hub's own baseline is still warming up.
@Test func appleHrvRowUsesTheRecoveryNormal() {
    let rec = decideRecoveryNormals(hrv: PersonalNormalResult(median: 30, low: 24.6, high: 35.4, sd: 5, n: 22), rhr: nil)
    #expect(rec["hrv"] == 25...35)
    #expect(rec["rhr"] == nil)
    let s = fxSignal("hrv", "HRV (7-day)", value: 14, status: .amber, note: "Apple baseline warming up (12/28)")
    let m = decideSignalRowModel(s, normal: nil, recoveryNormal: rec["hrv"])
    #expect(m.normal == 25...35)
    #expect(m.detail == nil)
    // Without any normal it is still honest.
    #expect(decideSignalRowModel(s, normal: nil).detail == "your normal — Calibrating")
    // The rationale's sentence reads the same band.
    let rows = gateRationaleCountedRows(signals: [s], normals: [:], recoveryNormals: rec, load: nil)
    #expect(rows.first?.sentence == "Under your 25–35 normal.")
}

// signal-normals: the rationale's Load row and the score card's Load driver say the same word.
@Test func rationaleLoadWordMatchesTheCard() {
    func comp(_ s: RecoveryComponentStatus) -> RecoveryComponent { RecoveryComponent(key: .load, status: s, value: nil, z: nil, normalN: 0) }
    let noReading = RecoveryScoreResult(status: .ok, score: 5, raw: -2, components: [comp(.noReading)], nights: 22)
    let card = RecoveryCardModel.make(result: noReading, reasonWord: nil, sleepGoalH: 7)
    let cardWord = card.drivers.first { $0.id == "load" }?.word
    let row = gateRationaleCountedRows(signals: [], normals: [:], load: nil,
                                       loadMissing: gateRationaleLoadMissingReason(noReading)).last
    #expect(row?.status.word == cardWord)
    let cal = RecoveryScoreResult(status: .ok, score: 5, raw: -2, components: [comp(.calibrating)], nights: 22)
    let calWord = RecoveryCardModel.make(result: cal, reasonWord: nil, sleepGoalH: 7).drivers.first { $0.id == "load" }?.word
    #expect(gateRationaleCountedRows(signals: [], normals: [:], load: nil,
                                     loadMissing: gateRationaleLoadMissingReason(cal)).last?.status.word == calWord)
}

// KpiDetail-caption: once the band exists the chart legend and the table's "28-day normal" row say so.
@Test func kpiDetailLegendAndTableFollowTheNormal() {
    let n = PersonalNormalResult(median: 28.4, low: 25.2, high: 31.6, sd: 2, n: 22)
    #expect(kpiDetailLegendText(n, decimals: 0) == "shaded = your normal 25–32 · dashed = median 28")
    #expect(kpiDetailLegendText(nil, decimals: 0) == kpiDetailLegend)
    let rows = kpiDetailTableRows(history: [("2026-09-26", 30)], value: 30, unit: "ms", decimals: 0, normal: n)
    #expect(rows.first { $0.id == "normal" }?.value == "25–32 ms")
    let none = kpiDetailTableRows(history: [("2026-09-26", 30)], value: 30, unit: "ms", decimals: 0)
    #expect(none.first { $0.id == "normal" }?.value == "— Calibrating")
}

// nutrition-normal: the macro panel's NormalBar gets the 28-day normal once there are 14 days in it.
@Test func nutritionMacroNormalFromTheRowsOnScreen() throws {
    let today = "2026-09-27"
    let rows = try (1...30).map { k in
        NutritionDailyRow(date: try CalendarMath.addDays(today, -k), kcalConsumed: Double(1800 + (k % 5) * 50), proteinG: 120)
    }
    let n = kpiMacroNormal(rows: rows, macro: .kcal, today: today)
    #expect(n != nil)
    #expect(n.map { $0.low <= $0.median && $0.median <= $0.high } == true)
    // Under 14 days in the normal window: honest nil ("Calibrating").
    #expect(kpiMacroNormal(rows: Array(rows.prefix(19)), macro: .kcal, today: today) == nil)
}

// Trends-window: Today (Trends' source) fetches 42 days — the 28-day normal ends at today−7 and
// starts at today−34, so a 28-day fetch can never fill it.
actor WindowRecordingProvider: HealthDataProvider {
    nonisolated let capabilities: DataCapability = .hubAll
    private nonisolated let inner = MockDataProvider()
    private(set) var gateWindows: [Int] = [], recoveryWindows: [Int] = []
    func health() async throws -> HealthResponse { try await inner.health() }
    func gate(windowDays: Int) async throws -> GateResponse { gateWindows.append(windowDays); return try await inner.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try await inner.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await inner.morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { recoveryWindows.append(windowDays); return try await inner.recovery(windowDays: windowDays) }
    func syncStatus() async throws -> SyncStatus { try await inner.syncStatus() }
}

@Test @MainActor func todayFetchesTheFortyTwoDayNormalWindow() async throws {
    let p = WindowRecordingProvider()
    let vm = TodayViewModel(provider: p, cache: OfflineCache(db: try AppDatabase.inMemory()))
    await vm.load()
    #expect(TodayViewModel.trendWindowDays == 42)
    #expect(await p.gateWindows == [42])
    #expect(await p.recoveryWindows == [42])
}

// GateConfig-copy → W-TGT L3: the cap row lives in Targets › Limits (the user's own number, "No
// cap" without one); the sleep goal is a Goal the user types (D2), no gate-rule line.
@Test func targetsCapReadsAsUserInput() {
    let rows = TargetsRows.limits(.empty, today: "2026-09-28")
    #expect(rows.first?.title == "HR cap")
    #expect(rows.first?.value == "No cap")
    #expect(!TargetsRows.limitsFooter.lowercased().contains("not configurable"))
}

// gallery: every gallery/sweep screen gets a seeded recovery insight (the mock's 42 deterministic
// days), so the score card, ring and bands render a real score — not "— No data".
@Test @MainActor func galleryFixtureHasARealScoreAndNormals() throws {
    let s = try #require(RecoveryInsightService.galleryFixture)
    #expect(s.result?.status == .ok)
    #expect(s.result?.score != nil)
    #expect(s.normal(for: .hrv) != nil)
    #expect(s.reasonWord == nil)
}

@Test func galleryPreviewInjectsTheRecoveryInsight() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/JIFeatures/Today/NativeScreenSupport.swift")
    let src = try String(contentsOf: url, encoding: .utf8)
    #expect(src.contains(".environment(\\.recoveryInsight, RecoveryInsightService.galleryFixture)"))
}
