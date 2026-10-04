import Foundation
import Testing
import JICore
import JICompute
@testable import JIFeatures

// B-104 p2: the HRV KPI detail's merged series — Garmin era (est., × 0.95 hub-side) + Watch nights,
// the 2026-09-13..18 hole a gap, band/average/28-day count Watch-only.

private func iso(_ d: Date) -> String {
    let f = DateFormatter(); f.calendar = trainingStripCalendar; f.timeZone = trainingStripCalendar.timeZone
    f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
}
private func days(_ from: String, _ to: String) -> [String] {
    var out: [String] = []; var d = trainingStripDate(from)!; let end = trainingStripDate(to)!
    while d <= end { out.append(iso(d)); d = trainingStripCalendar.date(byAdding: .day, value: 1, to: d)! }
    return out
}

/// Garmin 2026-07-01..09-12 (Sep 1 missing), hole 09-13..18, Watch 09-19..10-04.
private let garminDays = days("2026-07-01", "2026-09-12").filter { $0 != "2026-09-01" }
private let watchDays = days("2026-09-19", "2026-10-04")
private var sourceDays: [RecoveryInputDay] {
    garminDays.map { RecoveryInputDay(date: $0, hrvMs: 38, hrvSrc: "garmin") }
        + days("2026-09-13", "2026-09-18").map { RecoveryInputDay(date: $0) }
        + watchDays.map { RecoveryInputDay(date: $0, hrvMs: 45, hrvSrc: "apple") }
}
/// The screen's history: Watch nights only (`/vitals/recovery`'s Apple RMSSD).
private var history: [(date: String, value: Double?)] { watchDays.map { ($0, 45.0) } }

/// B-109: named suite so `-only-testing:JIFeaturesTests/B104HrvMergedSeriesTests` selects these tests.
@Suite struct B104HrvMergedSeriesTests {
    @Test func mergedSeriesGolden90D() {
        let filtered = kpiSourceFilteredHistory(history, metric: .hrv, sourceDays: sourceDays)
        let pts = kpiHrvMergedPoints(history: filtered, sourceDays: sourceDays, range: .quarter)
        // 90 days ending 10-04 start 07-07: Garmin 07-07..09-12 minus 09-01 = 67, Watch 16.
        #expect(pts.first.map { iso($0.date) } == "2026-07-07")
        #expect(pts.last.map { iso($0.date) } == "2026-10-04")
        #expect(pts.filter(\.isEstimate).count == 67)
        #expect(pts.filter { !$0.isEstimate }.count == 16)
        #expect(pts.filter(\.isEstimate).allSatisfy { $0.value == 38 })
        #expect(kpiHrvSourceCountText(pts) == "16 Watch + 67 Garmin")
        // Runs: Garmin to 08-31 (a 1-night miss is bridged), Garmin on, then the hole splits Watch off.
        let segs = kpiHrvSegments(pts)
        #expect(segs.count == 2)
        #expect(segs.map(\.source) == [.garmin, .apple])
        #expect(segs.map { $0.points.count } == [67, 16])
        #expect(segs.map { iso($0.points.last!.date) } == ["2026-09-12", "2026-10-04"])
    }

    @Test func holeLongerThanGapDaysSplitsSameSourceRun() {
        let src = ["2026-08-01", "2026-08-02", "2026-08-06", "2026-08-07"].map { RecoveryInputDay(date: $0, hrvMs: 40, hrvSrc: "garmin") }
        let pts = kpiHrvMergedPoints(history: [], sourceDays: src, range: .month)
        #expect(kpiHrvSegments(pts).map { $0.points.count } == [2, 2])
    }

    @Test func watchOnlyHubKeepsTheOldScreen() {
        // Older hub: no hrv_src → every hrv is a Watch night; no Garmin row, no extra table row.
        let old = watchDays.map { RecoveryInputDay(date: $0, hrvMs: 45) }
        let filtered = kpiSourceFilteredHistory(history, metric: .hrv, sourceDays: old)
        #expect(filtered.compactMap(\.value).count == 16)
        let pts = kpiHrvMergedPoints(history: filtered, sourceDays: old, range: .quarter)
        #expect(pts.count == 16 && !pts.contains(where: \.isEstimate))
        #expect(kpiHrvSegments(pts).count == 1)
        let rows = kpiDetailTableRows(history: filtered, value: 45, unit: "ms", decimals: 0)
        #expect(kpiHrvTableRows(rows, merged: pts, range: .quarter) == rows)
    }

    @Test func garminNightsNeverEnterTheWatchBaseline() {
        // The band / 7-day avg / 28-day count read `history` filtered Watch-only — a Garmin row with a
        // value does not mark its night as the Watch's.
        let mixedHistory = garminDays.map { ($0, Optional(38.0)) } + history
        let filtered = kpiSourceFilteredHistory(mixedHistory, metric: .hrv, sourceDays: sourceDays)
        #expect(filtered.compactMap(\.value).allSatisfy { $0 == 45 })
        #expect(filtered.compactMap(\.value).count == 16)
    }

    @Test func tableGetsPerSourceRowAndRenamedWatchCount() {
        let filtered = kpiSourceFilteredHistory(history, metric: .hrv, sourceDays: sourceDays)
        let pts = kpiHrvMergedPoints(history: filtered, sourceDays: sourceDays, range: .month)
        let rows = kpiHrvTableRows(kpiDetailTableRows(history: filtered, value: 45, unit: "ms", decimals: 0), merged: pts, range: .month)
        #expect(rows.map(\.id) == ["last", "avg7", "normal", "counted", "sources"])
        #expect(rows[3].title == "Watch nights (28 d)")
        #expect(rows[4].title == "Nights counted")
        // 30 days ending 10-04 start 09-05: Garmin 09-05..09-12 = 8.
        #expect(rows[4].value == "16 Watch + 8 Garmin")
        #expect(rows[4].subtitle.contains("Garmin = est."))
    }
}
