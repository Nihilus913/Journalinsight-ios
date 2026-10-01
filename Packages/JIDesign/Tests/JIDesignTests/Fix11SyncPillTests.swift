import Foundation
import Testing
@testable import JIDesign

// W-FIX11 H1-15 (+H2-05): a sync pill never shows the green "today" check while the hub is offline.
@Test func h1_15_syncedPillOfflineIsNotTheTodayCheck() {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let sync = now.addingTimeInterval(-3_600)
    #expect(syncedPillStyle(sync, now: now, calendar: cal, offline: false) == .today)
    #expect(syncedPillStyle(sync, now: now, calendar: cal, offline: true) == .offline)
    #expect(syncedPillStyle(nil, now: now, calendar: cal, offline: true) == .never)
    #expect(syncedPillStyle(now.addingTimeInterval(-200_000), now: now, calendar: cal, offline: false) == .older)
}

// W-FIX11 H1-10: a sparkline whose last point is an earlier day never ends on "today".
@Test func h1_10_sparklineEndsOnItsLastDay() {
    #expect(sparklineAxisWords(count: 7).start == "6d ago" && sparklineAxisWords(count: 7).end == "today")
    let w = sparklineAxisWords(count: 7, endLabel: "30 Sep")
    #expect(w.start == "6d earlier" && w.end == "30 Sep")
}

// W-FIX11 H1-11 (+H2-17): VoiceOver reads Load 1.76 as 1.76, never "last 2".
@Test func h1_11_sparklineLabelKeepsTheDataPrecision() {
    #expect(sparklineAccessibilityLabel(points: [1.2, nil, 1.764], decimals: 0, unit: nil) == "last 1.76, 3 days")
    #expect(sparklineAccessibilityLabel(points: [62, 63], decimals: 0, unit: "bpm") == "last 63 bpm, 2 days")
    #expect(sparklineAccessibilityLabel(points: [79.4, 79.5], decimals: 0, unit: "kg") == "last 79.5 kg, 2 days")
    #expect(sparklineAccessibilityLabel(points: [nil], decimals: 0, unit: nil) == "no values yet")
}
