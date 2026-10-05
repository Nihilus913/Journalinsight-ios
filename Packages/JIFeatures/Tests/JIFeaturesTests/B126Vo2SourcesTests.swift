import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

/// RG-11 / B-126 — VO₂ max mixes Garmin (39–41) and Apple (25–26) estimates in one line
/// (40 → 25 cliff, headline "25.0"). One series per source: Apple solid, Garmin dashed "est.",
/// and the headline names the source of the newest reading.
/// Fixture = hub `GET /training/cardio-series?range=y` 2026-10-05 (tail of the vo2max array).
@MainActor
@Suite struct B126Vo2SourcesTests {
    static let today = "2026-10-05"
    static let cardio = CardioSeries(range: "y", from: "2025-10-05", to: today, runs: [], vo2max: [
        Vo2maxPoint(date: "2026-08-20", vo2max: 40.9, source: "garmin"),
        Vo2maxPoint(date: "2026-08-27", vo2max: 40.7, source: "garmin"),
        Vo2maxPoint(date: "2026-09-03", vo2max: 40.2, source: "garmin"),
        Vo2maxPoint(date: "2026-09-22", vo2max: 25.8, source: "apple"),
        Vo2maxPoint(date: "2026-09-28", vo2max: 25.0, source: "apple"),
    ])

    func make() -> ProgressViewModel {
        let m = ProgressViewModel(store: nil, provider: nil, cardioProvider: nil, prefStore: ProgressMemoryPrefs(),
                                  today: { Self.today })
        m.setCardio(Self.cardio)
        m.range = .sixMonths
        return m
    }

    @Test func oneSeriesPerSource() {
        let card = make().card(.vo2max)
        #expect(card.series.count == 2)
        let apple = card.series.first { $0.name == "Apple" }
        let garmin = card.series.first { $0.name == "Garmin est." }
        #expect(apple?.points.map(\.value) == [25.8, 25.0])
        #expect(apple?.dashed == false)
        #expect(garmin?.points.map(\.value) == [40.9, 40.7, 40.2])
        #expect(garmin?.dashed == true)
    }

    @Test func headlineNamesItsSource() {
        let card = make().card(.vo2max)
        #expect(!card.thin)
        #expect(card.headline == "25.0 Apple")
    }

    @Test func noCliffInsideAnySeries() {
        // No series mixes values more than 10 apart (the 40 → 25 cliff came from mixing sources).
        for s in make().card(.vo2max).series {
            let v = s.points.map(\.value)
            #expect((v.max() ?? 0) - (v.min() ?? 0) < 10, "series \(s.name) mixes sources")
        }
    }

    @Test func singleSourceKeepsOneSeriesAndNamesIt() {
        let m = ProgressViewModel(store: nil, provider: nil, cardioProvider: nil, prefStore: ProgressMemoryPrefs(),
                                  today: { Self.today })
        m.setCardio(CardioSeries(range: "y", from: "2025-10-05", to: Self.today, runs: [], vo2max: [
            Vo2maxPoint(date: "2026-08-20", vo2max: 40.9, source: "garmin"),
            Vo2maxPoint(date: "2026-08-27", vo2max: 40.7, source: "garmin"),
            Vo2maxPoint(date: "2026-09-03", vo2max: 40.2, source: "garmin"),
        ]))
        m.range = .sixMonths
        let card = m.card(.vo2max)
        #expect(card.series.map(\.name) == ["Garmin est."])
        #expect(card.headline == "40.2 Garmin est.")
    }
}
