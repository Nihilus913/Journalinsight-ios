import Testing
@testable import JICompute

/// B-94 b94p2 — hand-numbered goldens (card docs/waves/cards/B-94.md).
@Suite struct LiftSeriesTests {
    private let bench = "Barbell Bench Press"
    private func r(_ d: String, _ reps: Int?, _ kg: Double?, _ lift: String = "Barbell Bench Press",
                   src: String = "garmin", dur: Int? = nil) -> LiftSeries.Input {
        .init(lift: lift, date: d, reps: reps, weightKg: kg, durationS: dur, source: src)
    }

    @Test func benchThreeSessionsE1rmGolden() {
        // Epley: 8×50 → 63.3, 10×50 → 66.7, 5×60 → 70.0
        let rows = [r("2026-09-15", 5, 60), r("2026-09-01", 8, 50), r("2026-09-08", 10, 50), r("2026-09-08", 6, 50)]
        let s = LiftSeries.series(lift: bench, metric: .e1rm, inputs: rows)
        #expect(s.points.map(\.date) == ["2026-09-01", "2026-09-08", "2026-09-15"])
        #expect(s.points.map(\.value) == [63.3, 66.7, 70.0])
        #expect(s.sessionCount == 3 && !s.insufficient)
        #expect(LiftSeries.series(lift: bench, metric: .heaviest, inputs: rows).points.map(\.value) == [50, 50, 60])
        #expect(LiftSeries.series(lift: bench, metric: .volume, inputs: rows).points.map(\.value) == [400, 800, 300])
        #expect(LiftSeries.series(lift: bench, metric: .sets, inputs: rows).points.map(\.value) == [1, 2, 1])
        #expect(LiftSeries.series(lift: bench, metric: .reps, inputs: rows).points.map(\.value) == [8, 16, 5])
        #expect(LiftSeries.metrics(lift: bench, inputs: rows) == [.e1rm, .heaviest, .volume, .sets, .reps])
    }

    @Test func underThreeSessionsInsufficient() {
        let rows = [r("2026-09-01", 8, 50), r("2026-09-08", 10, 50), r("2026-09-08", 8, 50)]
        let s = LiftSeries.series(lift: bench, metric: .e1rm, inputs: rows)
        #expect(s.sessionCount == 2 && s.insufficient && s.points.count == 2)
        #expect(LiftSeries.series(lift: bench, metric: .e1rm, inputs: []).insufficient)
        #expect(LiftSeries.series(lift: bench, metric: .e1rm, inputs: []).points.isEmpty)
    }

    @Test func weekBucketPicksHeaviestSessionSumsVolumeAndSets() {
        // ISO week Mon 2026-09-07: 09-08 = 3×(10×50) e1RM 66.7, vol 1500; 09-10 = 2×(3×60) e1RM 66.0, vol 360.
        let rows = [r("2026-09-08", 10, 50), r("2026-09-08", 10, 50), r("2026-09-08", 10, 50),
                    r("2026-09-10", 3, 60), r("2026-09-10", 3, 60),
                    r("2026-09-14", 8, 50)]   // next week (Mon 09-14)
        let e = LiftSeries.series(lift: bench, metric: .e1rm, inputs: rows, bucket: .week)
        #expect(e.points == [.init(date: "2026-09-07", value: 66.0), .init(date: "2026-09-14", value: 63.3)])
        #expect(e.sessionCount == 3 && !e.insufficient)
        #expect(LiftSeries.series(lift: bench, metric: .heaviest, inputs: rows, bucket: .week).points.map(\.value) == [60, 50])
        #expect(LiftSeries.series(lift: bench, metric: .volume, inputs: rows, bucket: .week).points.map(\.value) == [1860, 400])
        #expect(LiftSeries.series(lift: bench, metric: .sets, inputs: rows, bucket: .week).points.map(\.value) == [5, 1])
        #expect(LiftSeries.series(lift: bench, metric: .reps, inputs: rows, bucket: .week).points.map(\.value) == [6, 8])
        #expect(LiftSeries.isoWeekMonday("2026-09-13") == "2026-09-07")   // Sunday stays in its ISO week
        #expect(LiftSeries.isoWeekMonday("2026-01-01") == "2025-12-29")
        #expect(LiftSeries.bucket(rangeDays: 182) == .week && LiftSeries.bucket(rangeDays: 30) == .session)
    }

    @Test func garminAndJiSameSessionCountOnce() {
        let rows = [r("2026-09-01", 8, 50), r("2026-09-01", 8, 50), r("2026-09-01", 8, 50),
                    r("2026-09-01", 8, 50, src: "logged"), r("2026-09-01", 8, 50, src: "logged"),
                    r("2026-09-01", 8, 50, src: "logged")]
        let ss = LiftSeries.sessions(lift: bench, inputs: rows)
        #expect(ss.count == 1)
        #expect(ss[0].sets == 3 && ss[0].reps == 24 && ss[0].volumeKg == 1200 && ss[0].source == "logged")
        #expect(LiftSeries.series(lift: bench, metric: .volume, inputs: rows).points.map(\.value) == [1200])
        // Garmin-only day keeps its rows.
        #expect(LiftSeries.dedupe([r("2026-09-02", 8, 50)]).count == 1)
    }

    @Test func bodyweightLiftHasNoE1rm() {
        let pu = "Pull-up"
        let rows = [r("2026-09-01", 8, nil, pu), r("2026-09-01", 6, 0, pu),
                    r("2026-09-04", 9, nil, pu), r("2026-09-08", 10, 0, pu)]
        #expect(LiftSeries.isBodyweight(lift: pu, inputs: rows))
        #expect(LiftSeries.metrics(lift: pu, inputs: rows) == [.sets, .reps])
        let e = LiftSeries.series(lift: pu, metric: .e1rm, inputs: rows)
        #expect(e.points.isEmpty && e.insufficient)
        let reps = LiftSeries.series(lift: pu, metric: .reps, inputs: rows)
        #expect(reps.points.map(\.value) == [14, 9, 10] && !reps.insufficient)
    }

    @Test func timedLiftLongestDuration() {
        let pl = "Plank"
        let rows = [r("2026-09-01", nil, nil, pl, dur: 60), r("2026-09-01", nil, nil, pl, dur: 90),
                    r("2026-09-03", nil, nil, pl, dur: 75)]
        #expect(LiftSeries.metrics(lift: pl, inputs: rows) == [.sets, .longestDuration])
        let d = LiftSeries.series(lift: pl, metric: .longestDuration, inputs: rows)
        #expect(d.points.map(\.value) == [90, 75] && d.insufficient)
    }
}
