import SwiftUI
import Testing
@testable import JIDesign

private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.locale = Locale(identifier: "en_US"); return c }
private let sep21 = Date(timeIntervalSince1970: 1_789_992_000) // 2026-09-21 12:00 UTC (a Monday)

@Test func weekStripEndsTodayAndMarksIt() {
    let days = weekStripDays(ending: sep21, marked: [], calendar: utc)
    #expect(days.count == 7)
    #expect(days.last?.isToday == true)
    #expect(days.dropLast().allSatisfy { !$0.isToday })
    #expect(days.map(\.initial) == ["T", "W", "T", "F", "S", "S", "M"])
}

@Test func weekStripMarksDaysWithActivity() {
    let yesterday = utc.date(byAdding: .day, value: -1, to: utc.startOfDay(for: sep21))!
    let days = weekStripDays(ending: sep21, marked: [yesterday], calendar: utc)
    #expect(days[5].marked && !days[6].marked)
}

@Test @MainActor func weekStripRenders() {
    expectRenders("WeekStrip", width: 360, height: 80) {
        WeekStrip(days: weekStripDays(ending: sep21, marked: [], calendar: utc), tint: .green, selected: .constant(nil))
    }
}
