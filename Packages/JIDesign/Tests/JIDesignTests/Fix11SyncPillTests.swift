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
