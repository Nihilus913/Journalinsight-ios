import Foundation
import Testing
import JICore
@testable import JIFeatures

// W-B102 C-1 — the BP-23a predicate. History mirrors prod plan.morning_verdict 2026-09-28..10-04.

private func d(_ iso: String) -> DayKey { DayKey(iso: iso)! }

private let prodWeek: [CheckInMorning] = [
    .init(day: d("2026-09-28"), verdict: "GO (auto-regulated) — Day 1 Full Upper + Z2 40min"),
    .init(day: d("2026-09-29"), verdict: "MODIFIED — swap intervals for easy Z2 30-40min"),
    .init(day: d("2026-09-30"), verdict: "GO (auto-regulated) — Day 2 Full Upper + Z2 60min"),
    .init(day: d("2026-10-01"), verdict: "GO (auto-regulated) — Long Zone 2 75-90min"),
    .init(day: d("2026-10-02"), verdict: "GO (auto-regulated) — Day 3 Full Upper + Z2 60min"),
    .init(day: d("2026-10-03"), verdict: "MODIFIED — swap intervals for easy Z2 30-40min"),
    .init(day: d("2026-10-04"), verdict: "REST day"),
]

private func allGo(_ today: String) -> [CheckInMorning] {
    (0..<7).map { CheckInMorning(day: d(today).adding(days: -$0), verdict: "GO (auto-regulated) — Z2") }
}

struct CheckInTriggerTests {
    @Test func twoAmberMorningsFire() throws {
        let r = CheckInTrigger.evaluate(CheckInInputs(today: d("2026-10-04"), mornings: prodWeek, lastCheckinDay: d("2026-10-03")))
        let p = try #require(r.prompt)
        #expect(p.rule == .amber2)
        #expect(p.title == "Two amber mornings in a row")
        #expect(p.body.contains("Oct 3 Modified, Oct 4 Rest"))
        #expect(p.morningsLine == "GO · GO · Modified · Rest → amber ×2")
        #expect(p.why.contains("does not change the verdict"))
    }

    @Test func amberEvidenceUsesFlaggedSignals() throws {
        let hrv = GateSignal(key: "hrv_day", label: "Overnight HRV", value: 21.4, unit: "ms", threshold: 25,
                             direction: .min, status: .amber)
        let ok = GateSignal(key: "sleep", label: "Sleep", value: 7.5, unit: "h", threshold: 7, direction: .min, status: .pass)
        let r = CheckInTrigger.evaluate(CheckInInputs(today: d("2026-10-04"), mornings: prodWeek, gateSignals: [hrv, ok]))
        let p = try #require(r.prompt)
        #expect(p.body.contains("Overnight HRV 21.4 ms (floor 25 ms)"))
        #expect(!p.body.contains("Sleep"))
    }

    @Test func goTodayIsQuiet() {
        #expect(CheckInTrigger.evaluate(CheckInInputs(today: d("2026-10-02"), mornings: allGo("2026-10-02"))) == .quiet)
    }

    @Test func fiveOfSevenIsCalibrating() {
        let five = Array(prodWeek.suffix(5))
        #expect(CheckInTrigger.evaluate(CheckInInputs(today: d("2026-10-04"), mornings: five)) == .calibrating(known: 5))
    }

    @Test func morningsOutsideTheWindowDoNotCount() {
        let old = (7..<14).map { CheckInMorning(day: d("2026-10-04").adding(days: -$0), verdict: "GO") }
        #expect(CheckInTrigger.evaluate(CheckInInputs(today: d("2026-10-04"), mornings: old)) == .calibrating(known: 0))
    }

    @Test func overrideWithoutReasonFires() throws {
        let o = VerdictOverride(date: "2026-10-04", choice: .full, reason: "  ", session: "Z2")
        let r = CheckInTrigger.evaluate(CheckInInputs(today: d("2026-10-04"), mornings: allGo("2026-10-04"), override: o))
        let p = try #require(r.prompt)
        #expect(p.rule == .overrideNoReason)
        #expect(p.body.contains("Full"))
    }

    @Test func overrideWithReasonOrAcceptIsQuiet() {
        let reasoned = VerdictOverride(date: "2026-10-04", choice: .full, reason: "Feel good despite metrics", session: "Z2")
        let accept = VerdictOverride(date: "2026-10-04", choice: .accept, reason: nil, session: "Z2")
        let old = VerdictOverride(date: "2026-10-01", choice: .rest, reason: nil, session: "Z2")
        for o in [reasoned, accept, old] {
            #expect(CheckInTrigger.evaluate(CheckInInputs(today: d("2026-10-04"), mornings: allGo("2026-10-04"), override: o)) == .quiet)
        }
    }

    @Test func threeDaysWithoutCheckinFires() throws {
        let r = CheckInTrigger.evaluate(CheckInInputs(today: d("2026-10-04"), mornings: allGo("2026-10-04"), lastCheckinDay: d("2026-10-01")))
        let p = try #require(r.prompt)
        #expect(p.rule == .noCheckin3)
        #expect(p.title == "3 days without a check-in")
        #expect(CheckInTrigger.evaluate(CheckInInputs(today: d("2026-10-04"), mornings: allGo("2026-10-04"), lastCheckinDay: d("2026-10-02"))) == .quiet)
    }

    @Test func noCheckinEverIsNotNoCheckin3() {
        #expect(CheckInTrigger.evaluate(CheckInInputs(today: d("2026-10-04"), mornings: allGo("2026-10-04"), lastCheckinDay: nil)) == .quiet)
    }

    @Test func checkinTodayOrSnoozeIsQuiet() {
        #expect(CheckInTrigger.evaluate(CheckInInputs(today: d("2026-10-04"), mornings: prodWeek, lastCheckinDay: d("2026-10-04"))) == .quiet)
        #expect(CheckInTrigger.evaluate(CheckInInputs(today: d("2026-10-04"), mornings: prodWeek, snoozedDay: d("2026-10-04"))) == .quiet)
        // yesterday's snooze does not silence today
        #expect(CheckInTrigger.evaluate(CheckInInputs(today: d("2026-10-04"), mornings: prodWeek, snoozedDay: d("2026-10-03"))).prompt?.rule == .amber2)
    }

    @Test func disabledIsOff() {
        #expect(CheckInTrigger.evaluate(CheckInInputs(today: d("2026-10-04"), mornings: prodWeek, enabled: false)) == .off)
    }

    @Test func amberBeatsTheOtherRules() {
        let o = VerdictOverride(date: "2026-10-04", choice: .full, reason: nil, session: "Z2")
        let r = CheckInTrigger.evaluate(CheckInInputs(today: d("2026-10-04"), mornings: prodWeek, override: o, lastCheckinDay: d("2026-09-20")))
        #expect(r.prompt?.rule == .amber2)
    }

    @Test func shortLabels() {
        #expect(CheckInMorning(day: d("2026-10-04"), verdict: "REST day").shortLabel == "Rest")
        #expect(CheckInMorning(day: d("2026-10-04"), verdict: "GO (auto-regulated) — x").shortLabel == "GO")
        #expect(CheckInMorning(day: d("2026-10-04"), verdict: "REDUCED (hrv) — y").shortLabel == "Reduced")
        #expect(!CheckInMorning(day: d("2026-10-04"), verdict: "REST day").isGo)
    }
}
