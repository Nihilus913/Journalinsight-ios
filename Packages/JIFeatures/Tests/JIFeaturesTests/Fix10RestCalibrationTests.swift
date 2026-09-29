import Foundation
import Testing
import JICore
import JICompute
import JIDesign
import JIPersistence
@testable import JIFeatures

/// W-FIX10 R-04 — after the 2026-09-29 Garmin-copy purge the hub marks the baseline calibrating
/// (HT DH-4, `/vitals/recovery-inputs` `calibration`). The phone must say "Calibrating · n of N
/// nights", never a score or band built on nights the hub does not count.

private nonisolated struct CalibratingInputs: RecoveryInputsProviding {
    var days: [RecoveryInputDay]
    var calibration: RecoveryCalibration?
    func recoveryInputs(date: String, windowDays: Int) async throws -> [RecoveryInputDay] { days }
    func recoveryInputsReport(date: String, windowDays: Int) async throws -> RecoveryInputsReport {
        RecoveryInputsReport(date: date, days: days, calibration: calibration)
    }
}

private let hubCalibrating = RecoveryCalibration(
    status: "calibrating", calibrating: true, nights: 4, nightsNeeded: 14,
    components: ["hrv": .init(status: "calibrating", nights: 4), "rhr": .init(status: "calibrating", nights: 10),
                 "sleep": .init(status: "calibrating", nights: 10), "load": .init(status: "ok", nights: 28)])

private func fullHistory(end: String = "2026-09-24") throws -> [RecoveryInputDay] {
    try (0..<42).reversed().map { k in
        RecoveryInputDay(date: try CalendarMath.addDays(end, -k), hrvMs: 40 + Double(k % 5), rhrBpm: 55 + Double(k % 3),
                         sleepH: 7 + Double(k % 4) * 0.25, deepH: 1, remH: 1.5, loadMin: 30 + Double(k % 6) * 10)
    }
}

@MainActor private func service(_ cal: RecoveryCalibration?) throws -> RecoveryInsightService {
    RecoveryInsightService(provider: CalibratingInputs(days: try fullHistory(), calibration: cal),
                           cache: OfflineCache(db: try AppDatabase.inMemory()),
                           now: { Date(timeIntervalSince1970: 0) }, dayKey: { _ in "2026-09-24" })
}

@Test func calibrationCaptionSaysNOfNNights() {
    #expect(recoveryCalibrationCaption(hubCalibrating, key: "hrv") == "Calibrating · 4 of 14 nights")
    #expect(recoveryCalibrationCaption(hubCalibrating, key: "rhr") == "Calibrating · 10 of 14 nights")
    #expect(recoveryCalibrationCaption(hubCalibrating, key: "load") == nil)
    #expect(recoveryCalibrationCaption(nil, key: "hrv") == nil)
    #expect(kpiCalibrationKey(.hrv) == "hrv" && kpiCalibrationKey(.rhr) == "rhr" && kpiCalibrationKey(.protein) == nil)
}

@Test func hubCalibratingWinsOverALocalScore() throws {
    let days = try fullHistory()
    let local = try #require(RecoveryInsightService.score(days: days, today: "2026-09-24"))
    #expect(local.status == .ok && local.score != nil)                     // 42 local days would score…
    let r = try #require(RecoveryInsightService.score(days: days, today: "2026-09-24", calibration: hubCalibrating))
    #expect(r.status == .calibrating && r.score == nil && r.raw == nil)    // …but the hub counts 4 real nights
    #expect(r.nights == 4 && r.nightsNeeded == 14)
    #expect(r.component(.hrv)?.status == .calibrating && r.component(.hrv)?.z == nil)
    #expect(r.component(.load)?.status == local.component(.load)?.status)  // load is settled hub-side
    // A settled hub block leaves the phone's own score alone.
    let ok = RecoveryCalibration(status: "ok", calibrating: false, nights: 28, nightsNeeded: 14)
    #expect(RecoveryInsightService.score(days: days, today: "2026-09-24", calibration: ok) == local)
}

@Test @MainActor func serviceDropsBandsAndSaysCalibrating() async throws {
    let s = try service(hubCalibrating)
    await s.refresh()
    #expect(s.calibration == hubCalibrating)
    #expect(s.result?.status == .calibrating && s.result?.score == nil)
    #expect(s.normal(for: .hrv) == nil && s.normal(for: .rhr) == nil)
    #expect(s.calibrationCaption(for: .hrv) == "Calibrating · 4 of 14 nights")
    #expect(s.loadReading?.normal != nil)                                   // load "ok" hub-side keeps its band
    // Decide's ring caption follows the hub counts.
    #expect(decideReadinessCaption(score: nil, nights: nil, recovery: s.result)
            == "Recovery needs 14 nights · 4 of 14 so far · Calibrating")

    let settled = try service(nil)
    await settled.refresh()
    #expect(settled.normal(for: .hrv) != nil && settled.calibrationCaption(for: .hrv) == nil)
}

@Test @MainActor func loadCalibratingKeepsMinutesDropsBand() async throws {
    var cal = hubCalibrating
    cal.components["load"] = .init(status: "calibrating", nights: 9)
    let s = try service(cal)
    await s.refresh()
    let r = try #require(s.loadReading)
    #expect(r.normal == nil && r.minutes > 0)
    #expect(recoveryCalibrationCaption(cal, key: "load") == "Calibrating · 9 of \(RecoveryScore.loadMinNormalN) nights")
}

@Test func recoveryCardHasNoBandWhileTheHubCalibrates() throws {
    let days = try (0..<42).reversed().map { k in
        RecoveryDay(date: try CalendarMath.addDays("2026-09-24", -k), rhrBpm: 55 + Double(k % 3), hrvWeeklyAvg: 45)
    }
    #expect(recoveryCardNormal(metric: .rhr, days: days, insightNormal: nil, today: "2026-09-24") != nil)
    #expect(recoveryCardNormal(metric: .rhr, days: days, insightNormal: nil, today: "2026-09-24", hubCalibrating: true) == nil)
}

@Test func kpiDetailNormalIsNilWhileCalibratingButKeepsTheSevenDayMean() throws {
    let pts: [(date: String, value: Double?)] = try (0..<42).reversed().map { (try CalendarMath.addDays("2026-09-24", -$0), 40.0 + Double($0 % 5)) }
    let open = kpiDetailNormal(points: pts, today: "2026-09-24", hubCalibrating: false)
    let cal = kpiDetailNormal(points: pts, today: "2026-09-24", hubCalibrating: true)
    #expect(open.normal != nil && cal.normal == nil)
    #expect(cal.sevenDay == open.sevenDay && cal.sevenDay != nil)
}

@Test @MainActor func kpiDetailReadsTheHubCalibrationForHrv() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let m = KpiDetailViewModel(metric: .hrv, healthProvider: CalibratingHealth(calibration: hubCalibrating),
                               nutritionProvider: MockDataProvider(), targetsProvider: MockDataProvider(), cache: cache)
    await m.load()
    #expect(m.calibration == hubCalibrating)
    #expect(m.calibrationCaption == "Calibrating · 4 of 14 nights")
    // Offline reopen (a provider without the route): the cached verdict still holds.
    let offline = KpiDetailViewModel(metric: .rhr, healthProvider: PlainHealth(), nutritionProvider: MockDataProvider(),
                                     targetsProvider: MockDataProvider(), cache: cache)
    await offline.load()
    #expect(offline.calibrationCaption == "Calibrating · 10 of 14 nights")
    // Any other metric never carries it.
    let protein = KpiDetailViewModel(metric: .protein, healthProvider: CalibratingHealth(calibration: hubCalibrating),
                                     nutritionProvider: MockDataProvider(), targetsProvider: MockDataProvider(), cache: cache)
    await protein.load()
    #expect(protein.calibrationCaption == nil)
}

/// The mock hub, plus the calibrating recovery-inputs envelope.
private nonisolated struct CalibratingHealth: HealthDataProvider, RecoveryInputsProviding {
    let calibration: RecoveryCalibration
    let base = MockDataProvider()
    var capabilities: DataCapability { base.capabilities }
    func health() async throws -> HealthResponse { try await base.health() }
    func gate(windowDays: Int) async throws -> GateResponse { try await base.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try await base.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await base.morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { try await base.recovery(windowDays: windowDays) }
    func syncStatus() async throws -> SyncStatus { try await base.syncStatus() }
    func recoveryInputs(date: String, windowDays: Int) async throws -> [RecoveryInputDay] { [] }
    func recoveryInputsReport(date: String, windowDays: Int) async throws -> RecoveryInputsReport {
        RecoveryInputsReport(date: date, days: [], calibration: calibration)
    }
}

/// The mock hub without the recovery-inputs route (on-device / offline).
private nonisolated struct PlainHealth: HealthDataProvider {
    let base = MockDataProvider()
    var capabilities: DataCapability { base.capabilities }
    func health() async throws -> HealthResponse { try await base.health() }
    func gate(windowDays: Int) async throws -> GateResponse { try await base.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try await base.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await base.morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { try await base.recovery(windowDays: windowDays) }
    func syncStatus() async throws -> SyncStatus { try await base.syncStatus() }
}
