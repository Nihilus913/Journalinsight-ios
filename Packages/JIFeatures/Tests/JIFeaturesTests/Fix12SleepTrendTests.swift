import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-FIX12 F12-3 (H2-09 family): Sleep detail said "Down" in its headline while the 28-day row
// right under it said "— Calibrating". The headline counted 14 readings in the last 28 days; the
// row's normal (`kpiDetailNormal`) needs them in the 4 weeks BEFORE this week. One rule now: no
// normal on the row = no direction word in the headline.
@Suite struct Fix12SleepTrendTests {
    let today = "2026-10-03"
    /// 18 nights ending yesterday: ≥ 14 in the last 28 days, but too few before this week for a normal.
    var recentNights: [(date: String, value: Double?)] {
        (1...18).reversed().map { back in
            let d = Calendar(identifier: .gregorian).date(byAdding: .day, value: -back, to: ISO8601DateFormatter().date(from: "\(today)T12:00:00Z")!)!
            return (String(d.ISO8601Format().prefix(10)), back == 1 ? 5.0 : 7.5)
        }
    }

    @Test func calibratingRowMeansNoTrendWord() {
        let normal = kpiDetailNormal(points: recentNights, today: today, hubCalibrating: false).normal
        #expect(normal == nil)
        let row = kpiDetailTableRows(history: recentNights, value: 5.0, unit: "h", decimals: 1, normal: normal).first { $0.id == "normal" }
        #expect(row?.value == "— \(JIMissingReason.calibrating.rawValue)")
        let status = kpiDetailStatus(history: recentNights, value: 5.0, unit: "h", decimals: 1,
                                     normalSet: normal != nil, valueDate: "2026-10-02", today: today)
        #expect(!["Up", "Down", "Steady"].contains(status.word))
        #expect(status.word == "— \(JIMissingReason.calibrating.rawValue)")
    }

    @Test func aSetNormalKeepsTheTrendWord() {
        let status = kpiDetailStatus(history: recentNights, value: 5.0, unit: "h", decimals: 1,
                                     normalSet: true, valueDate: "2026-10-02", today: today)
        #expect(status.word == "Down")
    }
}
