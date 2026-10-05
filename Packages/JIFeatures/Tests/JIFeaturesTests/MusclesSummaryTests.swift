import Foundation
import Testing
import JICompute
@testable import JIFeatures

/// B-90 p5 — the Muscles card / screen states from fixtures: populated, calibrating ("1 of 3
/// workouts per muscle" on one line), empty; the ranked order; the "Last: …" subtitle wording.
@Suite struct MusclesSummaryTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }
    // Thu 12 Nov 2026 09:12 Berlin.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 9, minute: 12))! }

    private func build(_ k: MusclesFixture.Kind) -> MusclesSummary {
        MusclesSummaryBuilder.build(MusclesFixture.input(k, now: now, calendar: calendar), calendar: calendar)
    }

    @Test func emptyHasNoNumbers() {
        let s = build(.empty)
        #expect(s.phase == .empty)
        #expect(s.rows.allSatisfy { $0.state == .noData && $0.ratio == nil })
        #expect(s.mapStates.isEmpty)
        #expect(MusclesText.lastLine(s, calendar) == nil)
        #expect(MusclesText.headline(s) == "No strength sessions yet")
        #expect(s.rows.count == 13)
    }

    @Test func calibratingAfterOneSession() {
        let s = build(.calibrating)
        #expect(s.phase == .calibrating)
        #expect(MusclesText.calibrationLine(s) == "1 of 3 workouts per muscle")
        #expect(s.row(.chest)?.state == .calibrating(1))
        #expect(s.row(.quads)?.state == .noData)
        #expect(MusclesText.rowDetail(s.row(.chest)!, calendar) == "1 of 3 workouts in 28 d")
        #expect(MusclesText.lastLine(s, calendar) == "Last: Upper B · Wed 18:42")
        // Ratio needs 28 d of history: never shown after one session.
        #expect(s.rows.allSatisfy { $0.ratio == nil })
    }

    @Test func populatedRanksWorstFirstAndCarriesReasons() {
        let s = build(.populated)
        #expect(s.phase == .populated)
        let ranks = s.rows.map(\.state.rank)
        #expect(ranks == ranks.sorted())
        #expect(s.rows.first?.state == .depleted)
        let sh = s.row(.shoulders)!
        #expect(sh.state == .depleted)
        #expect(sh.ratio != nil)
        #expect(MusclesText.rowDetail(sh, calendar).hasPrefix("14 h ago"))
        #expect(MusclesText.rowDetail(sh, calendar).contains("fresh ~"))
        #expect(s.row(.biceps)?.state == .recovered)
        #expect(s.row(.hamstrings)?.state == .noData)
        #expect(MusclesText.lastLine(s, calendar) == "Last: Shoulders · Wed 18:42")
        #expect(MusclesText.headline(s).hasSuffix("depleted"))
        // What counted (7 d) credits the shoulder press as primary.
        #expect(sh.counted.first?.exercise == "DB Shoulder Press")
        #expect(sh.counted.first?.weight == 1.0)
    }

    @Test func mapCollapsesFinerVocabularyToTheWorstState() {
        let s = build(.populated)
        // Bench credits front delts (secondary); the Shoulders shape shows the worse of the two.
        let worst = [s.row(.shoulders)?.state, s.row(.frontDelts)?.state].compactMap { $0 }.min()
        #expect(s.mapStates[.shoulders] == worst)
        #expect(s.mapStates[.hamstrings] == nil)
    }

    @Test func agoAndRatioWording() {
        #expect(MusclesText.ago(14.6) == "14 h ago")
        #expect(MusclesText.ago(120) == "5 d ago")
        var r = build(.populated).row(.shoulders)!
        r.ratio = 1.34; r.band = .high
        #expect(MusclesText.ratio(r) == "1.34 over")
        r.ratio = nil
        #expect(MusclesText.ratio(r) == "—")
    }
}
