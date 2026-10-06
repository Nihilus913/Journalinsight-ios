import Foundation
import Testing
import JICore
@testable import JIFeatures

/// RG-36 (B-104): RHR / Sleep detail name the sources their 28 nights actually count (6 Garmin
/// fills + 22 Watch nights → "Apple Watch + Garmin"), and Garmin nights are drawn Garmin-style.
@Suite struct RecoverySourceSubtitleTests {
    let today = "2026-10-05"

    /// 28 nights ending today: the 6 oldest are Garmin fills, the newest 22 the Watch's.
    func fixture() -> [RecoveryInputDay] {
        (0..<28).map { i in
            let date = DayKey(iso: today)!.adding(days: i - 27).iso
            let garmin = i < 6
            return RecoveryInputDay(date: date, rhrBpm: garmin ? 69 : 64, sleepH: 7,
                                    rhrSrc: garmin ? "garmin" : "apple", sleepSrc: garmin ? "garmin" : "apple")
        }
    }

    @Test func mixedNightsNameBothSources() {
        #expect(kpiDetailSubtitle(.rhr, sourceDays: fixture(), today: today) == "Overnight · Apple Watch + Garmin · while asleep")
        #expect(kpiDetailSubtitle(.sleep, sourceDays: fixture(), today: today) == "Apple Watch + Garmin · hub score")
    }

    @Test func watchOnlyNightsKeepAppleWatch() {
        let watch = fixture().map { var d = $0; d.rhrSrc = "apple"; d.sleepSrc = "apple"; return d }
        #expect(kpiDetailSubtitle(.rhr, sourceDays: watch, today: today) == kpiDetailSubtitle(.rhr))
        #expect(kpiDetailSubtitle(.rhr, sourceDays: [], today: today) == kpiDetailSubtitle(.rhr))
    }

    @Test func garminNightsOutsideTheWindowDoNotCount() {
        var days = fixture().map { var d = $0; d.rhrSrc = "apple"; return d }
        days.append(RecoveryInputDay(date: "2026-08-01", rhrBpm: 70, rhrSrc: "garmin"))
        #expect(kpiDetailSubtitle(.rhr, sourceDays: days, today: today) == kpiDetailSubtitle(.rhr))
    }

    @Test func garminNightsDrawnInGarminStyle() {
        let days = fixture()
        let history = days.map { (date: $0.date, value: $0.rhrBpm) }
        let pts = kpiSourcedNightPoints(history: history, sourceDays: days, metric: .rhr, range: .month)
        #expect(pts.count == 28)
        #expect(pts.filter(\.isEstimate).count == 6)
        let segs = kpiHrvSegments(pts)
        #expect(segs.map(\.isEstimate) == [true, false])
    }

    /// The RHR detail's caption (legend "dashed = median N") and the drawn median are one number.
    @Test func rhrCaptionMedianEqualsDrawnMedian() throws {
        let days = fixture()
        let history = days.map { (date: $0.date, value: $0.rhrBpm) }
        let r = kpiDetailNormal(points: history, today: "2026-10-06", hubCalibrating: false)
        let n = try #require(r.normal)
        #expect(kpiDetailLegendText(n, decimals: 0).hasSuffix("median \(kpiDetailNumber(n.median, decimals: 0))"))
    }
}
