import Testing
@testable import JICompute

/// B-89 R-3 — same fixture as HT tests/test_strength_records.py.
struct OneRepMaxTests {
    private func r(_ d: String, _ reps: Int, _ kg: Double, _ lift: String = "Barbell Bench Press") -> OneRepMax.Input {
        .init(lift: lift, date: d, reps: reps, weightKg: kg, source: "garmin")
    }

    @Test func epley() {
        #expect(OneRepMax.epley(weightKg: 50, reps: 1) == 50)
        #expect(OneRepMax.round1(OneRepMax.epley(weightKg: 50, reps: 12)) == 70.0)
        #expect(OneRepMax.round1(OneRepMax.epley(weightKg: 50, reps: 9)) == 65.0)
    }

    @Test func prsStrictTieNotRecordOutliersSkipped() throws {
        let rows = [r("2025-08-11", 9, 10), r("2026-07-22", 8, 50), r("2026-07-22", 8, 50),
                    r("2026-08-03", 12, 50), r("2026-08-03", 10, 50), r("2026-08-17", 12, 50),
                    r("2026-09-04", 9, 50), r("2026-09-04", 15, 40)]
        let h = try #require(OneRepMax.histories(rows).first)
        let s = Dictionary(uniqueKeysWithValues: h.sessions.map { ($0.date, $0) })
        #expect(s["2025-08-11"] == nil)
        #expect(h.sessions.first?.date == "2026-09-04")
        #expect(s["2026-07-22"]?.prs == [.e1rm, .heaviest, .volume])
        #expect(s["2026-08-03"]?.prs == [.e1rm, .volume])
        #expect(s["2026-08-17"]?.prs == [])
        #expect(s["2026-09-04"]?.volumeKg == 450 && s["2026-09-04"]?.e1rm == 65.0)
        #expect(h.records.bestE1rm?.value == 70.0 && h.records.bestE1rm?.date == "2026-08-03")
        #expect(h.records.bestE1rm?.set == .init(reps: 12, weightKg: 50))
        #expect(h.records.heaviest?.date == "2026-07-22")
        #expect(h.records.bestVolume?.value == 1100)
        // 65.0 vs best 70.0 of the prior 4 weeks → down 7 %
        #expect(OneRepMax.status(h) == .down(percent: 7))
    }

    @Test func dumbbellMinimumAndStatus() throws {
        let h = try #require(OneRepMax.histories([r("2026-09-04", 12, 12, "DB Shoulder Press"),
                                                   r("2026-09-04", 12, 3, "DB Shoulder Press")]).first)
        #expect(h.perHand)
        #expect(h.sessions.first?.sets == [.init(reps: 12, weightKg: 12)])
        #expect(h.records.bestE1rm?.value == 16.8)
        #expect(OneRepMax.status(h) == .first)
    }

    @Test func heldAndNewBest() throws {
        let held = try #require(OneRepMax.histories([r("2026-09-01", 9, 50), r("2026-09-04", 8, 50)]).first)
        #expect(OneRepMax.status(held) == .held)   // 63.3 vs 65.0 = 97 %
        let up = try #require(OneRepMax.histories([r("2026-09-01", 8, 50), r("2026-09-04", 9, 50)]).first)
        #expect(OneRepMax.status(up) == .newBest)
    }
}
