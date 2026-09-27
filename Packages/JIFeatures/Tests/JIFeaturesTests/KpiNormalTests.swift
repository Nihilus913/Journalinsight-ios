import Foundation
import Testing
import JICore
import JICompute
import JIDesign
@testable import JIFeatures

// B-57 W3 S2 — real 28-day normal bands on Recovery, KpiDetail and Trends (display-only).

private func s2Source(_ relative: String) throws -> String {
    let pkg = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: pkg.appending(path: relative), encoding: .utf8)
}

@Test func kpiNormalFromThePlottedSeries() throws {
    let pts: [(date: String, value: Double?)] = try (0..<40).map { k in
        (try CalendarMath.addDays("2026-09-24", -k), k == 3 ? nil : 27 + Double(k % 4))
    }
    let r = KpiNormal.make(points: pts, today: "2026-09-24")
    #expect(r.normal?.n == 28)
    #expect(r.sevenDay != nil)
    #expect(KpiNormal.caption(r.normal, decimals: 0).hasPrefix("your normal "))
}

@Test func kpiNormalCalibratingUnder14() throws {
    let pts: [(date: String, value: Double?)] = try (0..<15).map { (try CalendarMath.addDays("2026-09-24", -$0), 50) }
    let r = KpiNormal.make(points: pts, today: "2026-09-24")
    #expect(r.normal == nil)
    #expect(KpiNormal.caption(r.normal, decimals: 0) == "Calibrating")
}

@Test func kpiNormalIgnoresNonFiniteValues() throws {
    let pts: [(date: String, value: Double?)] = try (0..<40).map { (try CalendarMath.addDays("2026-09-24", -$0), $0 % 2 == 0 ? .nan : 50) }
    let r = KpiNormal.make(points: pts, today: "2026-09-24")
    #expect(r.normal?.n == 14)
    #expect(r.normal?.median == 50)
}

@Test func captionRoundsToTheMetricDecimals() {
    let n = PersonalNormalResult(median: 28.4, low: 26.6, high: 30.2, sd: 1.8, n: 28)
    #expect(KpiNormal.caption(n, decimals: 0) == "your normal 27–30")
    #expect(KpiNormal.caption(n, decimals: 1) == "your normal 26.6–30.2")
}

@Test func statusAgainstTheNormal() {
    let n = PersonalNormalResult(median: 50, low: 45, high: 55, sd: 5, n: 28)
    #expect(KpiNormal.status(value: 50, normal: n) == .inNormal)
    #expect(KpiNormal.status(value: 40, normal: n) == .belowNormal)
    #expect(KpiNormal.status(value: 60, normal: n) == .aboveNormal)
    #expect(KpiNormal.status(value: 50, normal: nil) == .missing(.calibrating))
    #expect(KpiNormal.status(value: nil, normal: n) == .missing(.noData))
}

// MARK: - Trends

private func rhrNights(_ n: Int, today: String, value: (Int) -> Double) throws -> [RecoveryDay] {
    try (0..<n).map { k in
        RecoveryDay(date: try CalendarMath.addDays(today, -k), sleepScore: nil, sleepDurationSec: nil, rhrBpm: value(k),
                    bodyBatteryAvg: nil, readinessScore: nil, acwr: nil, hrvWeeklyAvg: nil)
    }
}

@Test func trendsCardGetsARealBandOnceThereAre14Nights() throws {
    let rec = try rhrNights(28, today: "2026-09-24") { 50 + Double($0 % 3) }
    let rhr = try #require(trendsCards(recovery: rec, daily: [], averages: nil, today: "2026-09-24").first { $0.id == "rhr" })
    #expect(rhr.normal != nil)
    #expect(rhr.normal!.n >= 14)
    #expect(rhr.status == .inNormal)
}

@Test func trendsCardStaysCalibratingUnder14() throws {
    let rec = try rhrNights(16, today: "2026-09-24") { _ in 54 }
    let rhr = try #require(trendsCards(recovery: rec, daily: [], averages: nil, today: "2026-09-24").first { $0.id == "rhr" })
    #expect(rhr.normal == nil)
    #expect(rhr.status == .missing(.calibrating))
}

@Test func trendsPassesTheBandToTheBar() throws {
    let view = try s2Source("Sources/JIFeatures/Today/TrendsView.swift")
    #expect(view.contains("normal: c.normal?.range, median: c.normal?.median"))
    #expect(!view.contains("NormalBar(value: c.value, normal: nil"))
}

// MARK: - Recovery

@Test func recoveryHrvBandPrefersTheGatesInputs() throws {
    let days = try rhrNights(28, today: "2026-09-24") { 50 + Double($0 % 3) }
    let gate = PersonalNormalResult(median: 30, low: 26, high: 34, sd: 3, n: 28)
    #expect(recoveryCardNormal(metric: .hrv, days: days, insightNormal: gate, today: "2026-09-24") == gate)
    #expect(recoveryCardNormal(metric: .rhr, days: days, insightNormal: gate, today: "2026-09-24") == gate)
    // No gate normal: the band of the plotted nights.
    #expect(recoveryCardNormal(metric: .rhr, days: days, insightNormal: nil, today: "2026-09-24")?.median == 51)
    // The sleep card plots the Garmin score: never an hours normal.
    #expect(recoveryCardNormal(metric: .sleep, days: days, insightNormal: gate, today: "2026-09-24") == nil)
}

@Test func recoveryDeepTileReadsTheGatesDeepSleep() {
    #expect(recoveryDeepText(hours: 1.2) == "1 h 12")
    #expect(recoveryDeepText(hours: nil) == "— not read")
    #expect(recoveryDeepText(hours: 0) == "— not read")
}

@Test func recoveryScreenDrawsTheBand() throws {
    let view = try s2Source("Sources/JIFeatures/Recovery/RecoveryView.swift")
    #expect(!view.contains("recoveryNormalText(nil)"))
    #expect(!view.contains("normal: nil,"))
    #expect(view.contains("@Environment(\\.recoveryInsight)"))
}

// MARK: - KpiDetail

@Test func kpiDetailDrawsTheBandAndPillsTheOneRule() throws {
    let view = try s2Source("Sources/JIFeatures/Kpi/KpiDetailView.swift")
    #expect(view.contains("KpiNormal.make("))
    #expect(view.contains("NormalBar("))
    // PF-04: the source line's pill is the one rule, never the screen's fetch time.
    #expect(view.contains("oneSyncPillDate("))
    #expect(!view.contains("fetchedAt: model.fetchedAt,\n"))
}
