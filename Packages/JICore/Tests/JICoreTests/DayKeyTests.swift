import Foundation
import Testing
@testable import JICore

/// W-KEYS K1: the one calendar-day key. The card's cases run with Europe/Zurich injected
/// (D1: the production zone is the phone's `TimeZone.current`).
@Suite struct DayKeyTests {
    let zurich = TimeZone(identifier: "Europe/Zurich")!

    private func instant(_ s: String) -> Date { try! Date(s, strategy: .iso8601) }

    @Test func lateEveningUTCIsNextZurichDay() {
        #expect(DayKey.today(now: instant("2026-10-03T22:30:00Z"), in: zurich).iso == "2026-10-04")
    }

    @Test func cetSwitchNight() {
        #expect(DayKey.today(now: instant("2026-10-25T00:30:00Z"), in: zurich).iso == "2026-10-25")
    }

    @Test func addingDaysAcrossDST() {
        #expect(DayKey(iso: "2026-10-24")!.adding(days: 2) == DayKey(iso: "2026-10-26")!)
        #expect(DayKey(iso: "2026-03-28")!.adding(days: 2).iso == "2026-03-30")
        #expect(DayKey(iso: "2026-01-01")!.adding(days: -1).iso == "2025-12-31")
    }

    @Test func mondayOfWeek() {
        #expect(DayKey(iso: "2026-10-05")!.mondayOfWeek.iso == "2026-10-05")
        #expect(DayKey(iso: "2026-10-04")!.mondayOfWeek.iso == "2026-09-28")
        #expect(DayKey(iso: "2026-10-07")!.mondayOfWeek.iso == "2026-10-05")
    }

    @Test func invalidIsoIsNil() {
        #expect(DayKey(iso: "2026-13-01") == nil)
        #expect(DayKey(iso: "2026-02-30") == nil)
        #expect(DayKey(iso: "garbage") == nil)
        #expect(DayKey(iso: "2026-1-01") == nil)
    }

    @Test func isoPrefixTenAcceptsTimestamps() {
        #expect(DayKey(iso: "2026-10-03T08:00:00Z")?.iso == "2026-10-03")
    }

    @Test func daysBetween() {
        #expect(DayKey(iso: "2026-10-24")!.days(to: DayKey(iso: "2026-10-26")!) == 2)
        #expect(DayKey(iso: "2026-10-26")!.days(to: DayKey(iso: "2026-10-24")!) == -2)
    }

    @Test func startDateIsZoneMidnight() {
        let d = DayKey(iso: "2026-10-25")!.startDate(in: zurich)
        #expect(d == instant("2026-10-24T22:00:00Z"))
        #expect(DayKey(date: d, in: zurich).iso == "2026-10-25")
    }

    @Test func otherZonesFollowThePhone() {
        let ny = TimeZone(identifier: "America/New_York")!
        #expect(DayKey(date: instant("2026-10-04T02:30:00Z"), in: ny).iso == "2026-10-03")
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        #expect(DayKey(date: instant("2026-10-03T16:00:00Z"), in: tokyo).iso == "2026-10-04")
    }

    @Test func comparableAndCodable() throws {
        #expect(DayKey(iso: "2026-09-30")! < DayKey(iso: "2026-10-01")!)
        let data = try JSONEncoder().encode([DayKey(iso: "2026-10-03")!])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-10-03\"]")
        let back = try JSONDecoder().decode([DayKey].self, from: data)
        #expect(back.first?.iso == "2026-10-03")
        #expect(throws: (any Error).self) { try JSONDecoder().decode([DayKey].self, from: Data("[\"x\"]".utf8)) }
    }

    // W-FIX13 F-1: one place for zone-free labels of a hub day key and the phone-zone calendar.
    @Test func labelsPrintTheKeysOwnDayInEveryZone() {
        let k = DayKey(iso: "2026-10-04")! // a Sunday
        #expect(k.weekday == 1)
        #expect(DayKey(iso: "2026-10-05")!.weekday == 2)
        #expect(k.string(format: "d MMM", locale: Locale(identifier: "en_GB")) == "4 Oct")
        #expect(k.string(format: "EEE", locale: Locale(identifier: "en_US")) == "Sun")
        #expect(k.formatted(Date.FormatStyle(locale: Locale(identifier: "en_GB")).day().month(.abbreviated)) == "4 Oct")
        #expect(k.string(template: "EEE d MMM", locale: Locale(identifier: "en_US")) == "Sun, Oct 4")
        // The label anchor is a fixed instant: identical whatever the phone's zone.
        #expect(DayKey(date: k.labelAnchor, in: TimeZone(identifier: "UTC")!).iso == "2026-10-04")
    }

    @Test func phoneCalendarAndFormatterUseTheInjectedZone() {
        let ny = TimeZone(identifier: "America/New_York")!
        #expect(DayKey.calendar(in: ny).timeZone == ny)
        #expect(DayKey.calendar(in: ny).identifier == .gregorian)
        #expect(DayKey.formatter("yyyy-MM-dd", in: ny).string(from: instant("2026-10-05T03:30:00Z")) == "2026-10-04")
    }
}

/// W-FIX13 F-1: "last night" freshness reads the night at 06:00 in the phone's zone, not UTC.
@Test func lastNightFreshnessUsesThePhoneZone() {
    let ny = TimeZone(identifier: "America/New_York")!
    let now = try! Date("2026-10-04T21:00:00Z", strategy: .iso8601) // 17:00 in New York
    // 06:00 New York on 10-03 = 10:00Z → 35 h old (fresh); 06:00 UTC would be 39 h (stale).
    #expect(KpiMetrics.isLastNightFresh(nightDate: "2026-10-03", now: now, in: ny))
    #expect(!KpiMetrics.isLastNightFresh(nightDate: "2026-10-03", now: now, in: TimeZone(identifier: "UTC")!))
    #expect(!KpiMetrics.isLastNightFresh(nightDate: "garbage", now: now, in: ny))
}
