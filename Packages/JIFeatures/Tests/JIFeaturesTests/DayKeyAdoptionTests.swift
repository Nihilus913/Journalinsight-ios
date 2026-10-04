import Foundation
import Testing
import JICore
@testable import JIFeatures

/// W-KEYS K3: the string↔Date round-trips go through `DayKey`.
@Suite struct DayKeyAdoptionTests {
    /// Scout risk 5: a stored goal day must show as that day in the picker west of UTC.
    @Test func goalDatePickerRoundTripsWestOfUTC() {
        let ny = TimeZone(identifier: "America/New_York")!
        let d = goalDatePickerDate("2026-12-31", in: ny)!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = ny
        #expect(cal.component(.day, from: d) == 31)
        #expect(goalDatePickerISO(d, in: ny) == "2026-12-31")
        #expect(goalDatePickerDate(nil, in: ny) == nil)
        #expect(goalDatePickerDate("2026-13-01", in: ny) == nil)
    }

    @Test func targetEditorRoundTrips() {
        #expect(targetEditorDay("2026-10-25").map(targetEditorISO) == "2026-10-25")
        #expect(targetEditorDay("nope") == nil)
    }

    @Test func kpiDayDistanceAcrossDST() {
        #expect(kpiDayDistance(from: "2026-10-24", to: "2026-10-26") == 2)
        #expect(kpiDayDistance(from: "2026-10-24T08:00:00", to: "2026-10-26") == 2)
        #expect(kpiDayDistance(from: "x", to: "2026-10-26") == nil)
    }

    @Test func planWeekStartIsMonday() {
        #expect(planWeekStart("2026-10-04") == "2026-09-28")
        #expect(planWeekStart("2026-10-05") == "2026-10-05")
        #expect(planWeekStart("bad") == nil)
    }

    /// W-FIX13 F-1: the Journal follows the phone's zone (D1), no longer a fixed Zurich calendar.
    @Test func journalCalendarFollowsThePhoneZone() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = DayKey.zone
        let lateEvening = cal.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 23, minute: 30))!
        #expect(JournalCalendar.toISO(lateEvening) == "2026-10-04")
        #expect(DayKey(iso: "2026-10-25")?.startDate == cal.date(from: DateComponents(year: 2026, month: 10, day: 25)))
    }

    // MARK: - W-FIX13 F-1: a phone in New York at 23:30 — every screen shows the local day

    private static let ny = TimeZone(identifier: "America/New_York")!
    /// Sun 4 Oct 2026, 23:30 in New York (already Mon 5 Oct 03:30 UTC).
    private static var nyLateEvening: Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = ny
        return cal.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 23, minute: 30))!
    }

    @Test func newYorkLateEveningKeyIsTheLocalDay() {
        let key = DayKey.today(now: Self.nyLateEvening, in: Self.ny)
        #expect(key.iso == "2026-10-04")
        let en = Locale(identifier: "en_US"), gb = Locale(identifier: "en_GB")
        // The screens re-print that key as itself (zone-free), never the UTC day after.
        #expect(recoveryNightLabel(key.iso) == "Sun")
        #expect(GateRationaleView.weekdayLabel(key.iso, locale: en) == "Sun")
        #expect(GateRationaleViewModel.lastThreeDates(anchor: key.iso) == ["2026-10-04", "2026-10-03", "2026-10-02"])
        #expect(GateRationaleViewModel.lastThreeDates(anchor: "2026-03-30") == ["2026-03-30", "2026-03-29", "2026-03-28"])
        #expect(goalsSetupDateLabel(key.iso) == "4 Oct 2026")
        #expect(targetsLongDate(key.iso) == "4 Oct 2026")
        #expect(targetsShortDate(key.iso) == "4 Oct")
        #expect(kpiShortDay(key.iso) == "4 Oct")
        #expect(readinessDateText(key.iso, locale: gb).contains("Sun"))
        #expect(readinessDateText(key.iso, locale: gb).contains("4"))
        #expect(StrengthHistoryView.dateTitle(key.iso).contains("4"))
        #expect(StrengthHistoryView.dateTitle("2026-10-0") == "2026-10-0")
    }

    @MainActor @Test func backloadEpochStartsAtNewYorkMidnight() {
        let vm = HealthBackloadViewModel(runner: FakeBackloadRunner(), now: { Self.nyLateEvening }, hrvPrefs: nil, timeZone: Self.ny)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = Self.ny
        let c = cal.dateComponents([.year, .month, .day, .hour], from: vm.defaultRange.from)
        #expect([c.year, c.month, c.day, c.hour] == [2025, 5, 27, 0])
    }

    @Test func lastNightFreshnessInNewYork() {
        // Night of 10-04 read 06:00 New York; at 23:30 the same evening it is still "last night".
        #expect(KpiMetrics.isLastNightFresh(nightDate: "2026-10-04", now: Self.nyLateEvening, in: Self.ny))
    }
}
