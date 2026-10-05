import Foundation
import Testing
import JICore
import JICompute
import JIDesign
@testable import JIFeatures

/// B-94 b94p4 — in-memory `PrefStore` stand-in (a "relaunch" = a new VM over the same store).
nonisolated final class ProgressMemoryPrefs: JIPrefStoring, @unchecked Sendable { // @unchecked: tests drive it from one actor
    var blobs: [String: Data] = [:]
    func get<T: Decodable>(_ key: String, as: T.Type) throws -> T? {
        try blobs[key].map { try JSONDecoder().decode(T.self, from: $0) }
    }
    func set<T: Encodable>(_ key: String, _ value: T) throws { blobs[key] = try JSONEncoder().encode(value) }
    func remove(_ key: String) throws { blobs[key] = nil }
}

nonisolated final class ProgressFakeCardio: CardioSeriesProviding, @unchecked Sendable { // @unchecked: one test actor
    var out: CardioSeries
    var asked: [String] = []
    init(_ out: CardioSeries) { self.out = out }
    func cardioSeries(range: String) async throws -> CardioSeries { asked.append(range); return out }
}

@MainActor
@Suite struct ProgressViewModelTests {
    static let today = "2026-10-05"

    /// Bench: 3 Garmin sessions in Sep (one a week apart), row: 2 sessions (thin).
    static let hub = StrengthRecordsOut(lifts: [
        StrengthRecordLiftOut(lift: "Barbell Bench Press", sessions: [
            .init(date: "2026-09-01", sets: [.init(reps: 5, weightKg: 45)], sources: ["garmin"]),
            .init(date: "2026-09-15", sets: [.init(reps: 5, weightKg: 47.5)], sources: ["garmin"]),
            .init(date: "2026-10-01", sets: [.init(reps: 5, weightKg: 50), .init(reps: 3, weightKg: 50)], sources: ["garmin"]),
        ]),
        StrengthRecordLiftOut(lift: "Barbell Row", sessions: [
            .init(date: "2026-09-02", sets: [.init(reps: 8, weightKg: 40)], sources: ["garmin"]),
            .init(date: "2026-09-16", sets: [.init(reps: 8, weightKg: 42)], sources: ["garmin"]),
        ]),
    ])

    static let cardio = CardioSeries(range: "y", from: "2025-10-05", to: today, runs: [
        CardioRun(activityId: 1, date: "2026-08-10", type: "running", source: "garmin", distanceM: 5000, durationSec: 2700, paceSecPerKm: 540, avgHr: 150),
        CardioRun(activityId: 2, date: "2026-09-10", type: "running", source: "garmin", distanceM: 6000, durationSec: 3000, paceSecPerKm: 500, avgHr: nil),
        CardioRun(activityId: 3, date: "2026-10-03", type: "running", source: "garmin", distanceM: 4000, durationSec: 1900, paceSecPerKm: 475, avgHr: 148),
    ], vo2max: [Vo2maxPoint(date: "2026-09-01", vo2max: 40.2, source: "garmin"), Vo2maxPoint(date: "2026-10-01", vo2max: 40.9, source: "garmin")])

    func make(_ prefs: ProgressMemoryPrefs = ProgressMemoryPrefs()) -> ProgressViewModel {
        let m = ProgressViewModel(store: nil, provider: nil, cardioProvider: nil, prefStore: prefs, today: { Self.today })
        m.setHub(Self.hub); m.setCardio(Self.cardio)
        return m
    }

    let bench = ProgressChartID.lift(key: "Barbell Bench Press", metric: .e1rm)
    let row = ProgressChartID.lift(key: "Barbell Row", metric: .e1rm)
    let benchVolume = ProgressChartID.lift(key: "Barbell Bench Press", metric: .volume)

    @Test func defaultsShowLeadMetricPerLiftThenPaceAndVo2() {
        let m = make()
        #expect(m.prefs == ProgressChartPrefs())
        #expect(m.strengthCards.map(\.id) == [bench, row])   // most sessions first
        #expect(m.cardioCards.map(\.id) == [.run(.pace), .vo2max])
        #expect(m.catalogue.contains(benchVolume))
        #expect(m.subtitle == "Nothing pinned · Strength + Cardio")
    }

    @Test func pinnedOrderDrivesCardOrder() {
        let m = make()
        m.pin(row); m.pin(benchVolume); m.pin(bench)
        #expect(m.strengthCards.map(\.id) == [row, benchVolume, bench])
        #expect(m.strengthCards.allSatisfy { $0.pinned })
        m.movePins(fromOffsets: IndexSet(integer: 2), toOffset: 0)   // bench to the top
        #expect(m.strengthCards.map(\.id) == [bench, row, benchVolume])
        m.pin(.vo2max)
        #expect(m.cardioCards.map(\.id) == [.vo2max, .run(.pace)])
        #expect(m.subtitle == "4 pinned · Strength + Cardio")
    }

    @Test func pinsAndOrderSurviveRelaunch() {
        let store = ProgressMemoryPrefs()
        let m = make(store)
        m.pin(benchVolume); m.pin(bench); m.setHidden(row, true)
        m.move(bench, direction: -1)
        let again = make(store)   // a new VM over the same PrefStore = app relaunch
        #expect(again.prefs.pinned == [bench, benchVolume])
        #expect(again.strengthCards.map(\.id) == [bench, benchVolume])   // row hidden
        #expect(store.blobs[ProgressChartSelection.prefKey] != nil)
    }

    @Test func menuPinTogglesAndHideRemovesCard() {
        let m = make()
        m.togglePin(.run(.pace))
        #expect(m.prefs.pinned == [.run(.pace)])
        m.togglePin(.run(.pace))
        #expect(m.prefs.pinned.isEmpty)
        m.setHidden(.vo2max, true)
        #expect(m.cardioCards.map(\.id) == [.run(.pace)])
        m.setHidden(.vo2max, false)
        #expect(m.cardioCards.map(\.id) == [.run(.pace), .vo2max])
    }

    @Test func thinStateUnderThreeSessions() {
        let m = make()
        let rowCard = m.card(row)
        #expect(rowCard.count == 2)
        #expect(rowCard.thin)
        #expect(rowCard.headline == nil)          // never a false number
        let vo2 = m.card(.vo2max)
        #expect(vo2.thin)                          // 2 readings
        let benchCard = m.card(bench)
        #expect(!benchCard.thin)
        #expect(benchCard.count == 3)
        // Epley 50 × (1 + 5/30) = 58.3
        #expect(benchCard.headline == "58.3\u{202F}kg")
    }

    @Test func rangeSwitchCutsSeries() {
        let m = make()
        m.range = .sixMonths
        #expect(m.card(.run(.pace)).count == 3)
        #expect(!m.card(bench).thin)
        #expect(m.card(bench).caption.contains("heaviest session per week"))
        m.range = .month
        #expect(m.card(.run(.pace)).count == 2)   // 09-10 and 10-03 within 30 days
        #expect(m.card(bench).count == 2)         // 09-15 and 10-01
        #expect(m.card(bench).thin)
        #expect(!m.card(bench).caption.contains("per week"))
        m.range = .week
        #expect(m.card(.run(.pace)).points.count == 1)
        #expect(m.card(.run(.hr)).count == 1)
    }

    @Test func volumeIsASumChartAndGroupsWithNarrowNoBreakSpace() {
        let m = make()
        m.range = .year
        let v = m.card(benchVolume)
        #expect(v.kind == .sum)
        // week of 2026-09-28: 5×50 + 3×50 = 400
        #expect(v.points.last?.value == 400)
        #expect(ProgressFormat.grouped(1350) == "1\u{202F}350")
        #expect(ProgressFormat.grouped(1234567.25, fractionDigits: 1) == "1\u{202F}234\u{202F}567.2")
        #expect(ProgressFormat.value(475, metric: .run(.pace)) == "7:55\u{202F}/km")
    }

    @Test func loadFetchesCardioOnceAtWidestRange() async {
        let fake = ProgressFakeCardio(Self.cardio)
        let m = ProgressViewModel(store: nil, provider: nil, cardioProvider: fake, prefStore: nil, today: { Self.today })
        await m.load()
        #expect(fake.asked == [ProgressViewModel.cardioFetchRange])
        #expect(m.card(.run(.pace)).count == 3)
        #expect(m.strengthCards.isEmpty)   // no lifts → Strength empty state
        #expect(!m.loading)
    }
}
