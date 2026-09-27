import Foundation
import Testing
import JICore
import JICompute
import JIDesign
import JIPersistence
@testable import JIFeatures

/// B-57 W3 D3 — the phone computes the recovery score from the gate's own loader
/// (`GET /vitals/recovery-inputs`, D1) for the requested day, and never invents a number.

nonisolated struct RecoveryInputsFake: RecoveryInputsProviding {
    var days: [RecoveryInputDay]
    var error: HubError?
    func recoveryInputs(date: String, windowDays: Int) async throws -> [RecoveryInputDay] {
        if let error { throw error }
        return days.filter { $0.date <= date }
    }
}

/// Records the `date` the service asked for (the gate/phone same-day contract).
nonisolated final class RecordingInputs: RecoveryInputsProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _dates: [String] = []
    private var _windows: [Int] = []
    let days: [RecoveryInputDay]
    init(days: [RecoveryInputDay]) { self.days = days }
    var dates: [String] { lock.withLock { _dates } }
    var windows: [Int] { lock.withLock { _windows } }
    func recoveryInputs(date: String, windowDays: Int) async throws -> [RecoveryInputDay] {
        lock.withLock { _dates.append(date); _windows.append(windowDays) }
        return days.filter { $0.date <= date }
    }
}

private func recoveryHistory(_ n: Int, end: String = "2026-09-24") throws -> [RecoveryInputDay] {
    try (0..<n).reversed().map { k in
        RecoveryInputDay(date: try CalendarMath.addDays(end, -k), hrvMs: 40 + Double(k % 5), rhrBpm: 55 + Double(k % 3),
                         sleepH: 7 + Double(k % 4) * 0.25, deepH: 1 + Double(k % 3) * 0.1, remH: 1.5 + Double(k % 2) * 0.2,
                         loadMin: 30 + Double(k % 6) * 10)
    }
}

private func seriesDays(_ days: [RecoveryInputDay]) -> [RecoverySeriesDay] {
    days.map { RecoverySeriesDay(date: $0.date, hrvMs: $0.hrvMs, rhrBpm: $0.rhrBpm, sleepH: $0.sleepH,
                                 deepH: $0.deepH, remH: $0.remH, loadMin: $0.loadMin) }
}

@MainActor private func recoveryService(_ p: (any RecoveryInputsProviding)?, day: String = "2026-09-24",
                                        cache: OfflineCache? = nil) throws -> RecoveryInsightService {
    RecoveryInsightService(provider: p, cache: try cache ?? OfflineCache(db: AppDatabase.inMemory()),
                           now: { Date(timeIntervalSince1970: 0) }, dayKey: { _ in day })
}

@Test @MainActor func serviceComputesForTheRequestedDay() async throws {
    let days = try recoveryHistory(45)
    let rec = RecordingInputs(days: days)
    let s = try recoveryService(rec)
    await s.refresh()
    let expected = try RecoveryScore.compute(days: seriesDays(days), today: "2026-09-24")
    #expect(rec.dates == ["2026-09-24"])
    #expect(rec.windows == [RecoveryInsightService.windowDays])
    #expect(s.today == "2026-09-24")
    #expect(s.result == expected)
    #expect(s.result?.status == .ok && s.result?.score != nil)
    #expect(s.reasonWord == nil)
    #expect(s.normal(for: .hrv)?.n == 28)
    #expect(s.sevenDay(for: .hrv) != nil)
}

@Test @MainActor func noProviderSaysNoDataNeverAScore() async throws {
    let s = try recoveryService(nil)
    await s.refresh()
    #expect(s.result == nil && s.reasonWord == "No data")
    let card = RecoveryCardModel.make(result: s.result, reasonWord: s.reasonWord, sleepGoalH: 7)
    #expect(card.headline == "— No data" && !card.isLow && card.status == nil)
}

@Test @MainActor func emptyAnswerSaysNoData() async throws {
    let s = try recoveryService(RecoveryInputsFake(days: []))
    await s.refresh()
    #expect(s.result == nil && s.reasonWord == "No data")
}

/// Card exit (Review Focus 3): no Apple HRV last night = "missing", never 50, never "Recovery low".
@Test @MainActor func missingHrvTonightIsMissingNotFifty() async throws {
    var days = try recoveryHistory(45)
    days[days.count - 1].hrvMs = nil
    let s = try recoveryService(RecoveryInputsFake(days: days))
    await s.refresh()
    #expect(s.result?.status == .missing)
    #expect(s.result?.score == nil)
    let card = RecoveryCardModel.make(result: s.result, reasonWord: s.reasonWord, sleepGoalH: 7)
    #expect(card.headline == "— No data")
    #expect(!card.headline.contains("50") && !card.isLow && card.status == nil)
}

@Test @MainActor func calibratingCardSaysCalibratingAndTheBoardNote() async throws {
    let s = try recoveryService(RecoveryInputsFake(days: try recoveryHistory(20)))
    await s.refresh()
    #expect(s.result?.status == .calibrating)
    let card = RecoveryCardModel.make(result: s.result, reasonWord: s.reasonWord, sleepGoalH: 7)
    #expect(card.headline == "— Calibrating")
    #expect(card.note == "One score from overnight HRV, resting HR and sleep (length, deep, REM), each against your normal. It shows a number once all three have 14 nights.")
    #expect(card.drivers.map(\.label) == ["HRV", "Sleep", "Resting HR", "Load"])
}

@Test @MainActor func hubErrorFallsBackToTheCacheAndKeepsTheScore() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let ok = try recoveryService(RecoveryInputsFake(days: try recoveryHistory(45)), cache: cache)
    await ok.refresh()
    let offline = try recoveryService(RecoveryInputsFake(days: [], error: .network("down")), cache: cache)
    await offline.refresh()
    #expect(offline.result == ok.result)
    #expect(offline.result != nil)
}

@Test @MainActor func hubErrorWithNoCacheSaysNoData() async throws {
    let s = try recoveryService(RecoveryInputsFake(days: [], error: .network("down")))
    await s.refresh()
    #expect(s.result == nil && s.reasonWord == "No data")
}

@Test @MainActor func lastNightsAreOldestFirstWithGapsAsNil() async throws {
    var days = try recoveryHistory(10)
    days.removeAll { $0.date == "2026-09-22" }
    let s = try recoveryService(RecoveryInputsFake(days: days))
    await s.refresh()
    let nights = s.lastNights(.sleepH, count: 4)
    #expect(nights.map(\.date) == ["2026-09-21", "2026-09-22", "2026-09-23", "2026-09-24"])
    #expect(nights[1].value == nil && nights[0].value != nil)
}

@Test @MainActor func refreshIfStaleRefetchesOnlyWhenOldOrDayChanged() async throws {
    let rec = RecordingInputs(days: try recoveryHistory(45))
    var clock = Date(timeIntervalSince1970: 1_000_000)
    var day = "2026-09-24"
    let s = RecoveryInsightService(provider: rec, cache: OfflineCache(db: try AppDatabase.inMemory()),
                                   now: { clock }, dayKey: { _ in day })
    await s.refreshIfStale()
    await s.refreshIfStale()
    #expect(rec.dates.count == 1)
    clock = clock.addingTimeInterval(RecoveryInsightService.staleAfter + 1)
    await s.refreshIfStale()
    #expect(rec.dates.count == 2)
    day = "2026-09-25"
    await s.refreshIfStale()
    #expect(rec.dates == ["2026-09-24", "2026-09-24", "2026-09-25"])
}

@Test func cardWordsFollowTheBoard() throws {
    func comp(_ k: RecoveryComponentKey, _ s: RecoveryComponentStatus, _ v: Double?, _ z: Double?) -> RecoveryComponent {
        RecoveryComponent(key: k, status: s, value: v, z: z, normalN: 28)
    }
    let r = RecoveryScoreResult(status: .ok, score: 31, raw: 31.2,
                                components: [comp(.hrv, .ok, 25, -1.4), comp(.rhr, .noReading, nil, nil),
                                             comp(.sleep, .ok, 7.4, 0.8), comp(.load, .calibrating, nil, nil)],
                                nights: 28, nightsNeeded: 14)
    let card = RecoveryCardModel.make(result: r, reasonWord: nil, sleepGoalH: 7)
    #expect(card.headline == "31" && card.status == "Recovery low" && card.isLow)
    let words = Dictionary(uniqueKeysWithValues: card.drivers.map { ($0.id, $0.word ?? "") })
    #expect(words == ["hrv": "Low", "rhr": "No reading", "sleep": "Above goal", "load": "Calibrating"])
    #expect(card.drivers.first { $0.id == "hrv" }?.tint == .reduced)
    #expect(card.drivers.first { $0.id == "sleep" }?.tint == .sleep)
    #expect(card.drivers.first { $0.id == "rhr" }?.value == nil)
    #expect(card.drivers.allSatisfy { $0.tint != .go })
}

@Test func rhrAndLoadWordsFollowTheRawValue() throws {
    func comp(_ k: RecoveryComponentKey, _ z: Double) -> RecoveryComponent {
        RecoveryComponent(key: k, status: .ok, value: 1, z: z, normalN: 28)
    }
    let r = RecoveryScoreResult(status: .ok, score: 50, raw: 50,
                                components: [comp(.hrv, 1.2), comp(.rhr, -1.5), comp(.sleep, -1.1), comp(.load, 1.0)],
                                nights: 28, nightsNeeded: 14)
    let card = RecoveryCardModel.make(result: r, reasonWord: nil, sleepGoalH: 7)
    let byId = Dictionary(uniqueKeysWithValues: card.drivers.map { ($0.id, $0) })
    #expect(byId["hrv"]?.word == "High" && byId["hrv"]?.tint == nil)
    #expect(byId["rhr"]?.word == "High" && byId["rhr"]?.tint == .reduced)
    #expect(byId["load"]?.word == "Low" && byId["load"]?.tint == nil)
    #expect(byId["sleep"]?.word == "Below goal" && byId["sleep"]?.tint == .reduced)
    #expect(byId["hrv"]?.value == (1.2 + 3) / 6)
}

@Test func scoreAtThresholdIsNotLow() {
    let r = RecoveryScoreResult(status: .ok, score: 35, raw: 35, components: [], nights: 28, nightsNeeded: 14)
    let card = RecoveryCardModel.make(result: r, reasonWord: nil, sleepGoalH: 7)
    #expect(!card.isLow && card.status == "In your normal range" && card.headline == "35")
}
