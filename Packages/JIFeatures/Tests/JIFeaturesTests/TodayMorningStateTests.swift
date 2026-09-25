import Foundation
import Testing
import JICore
@testable import JIFeatures

@Suite struct TodayMorningStateTests {
    @Test func decideAdvancesOnlyOnGateResponse() {
        #expect(TodayMorningFlow.next(.decide, .gateResponded) == .coach)
        #expect(TodayMorningFlow.next(.decide, .coachAcknowledged) == .decide)
    }
    @Test func coachAdvancesOnlyOnAcknowledge() {
        #expect(TodayMorningFlow.next(.coach, .coachAcknowledged) == .day)
        #expect(TodayMorningFlow.next(.coach, .gateResponded) == .coach)
    }
    @Test func dayIsTerminalUntilNewVerdictDate() {
        #expect(TodayMorningFlow.next(.day, .gateResponded) == .day)
        #expect(TodayMorningFlow.next(.day, .coachAcknowledged) == .day)
        #expect(TodayMorningFlow.next(.day, .newVerdictDate) == .decide)
        #expect(TodayMorningFlow.next(.coach, .newVerdictDate) == .decide)
    }
    @Test func prefKeyIsPerVerdictDate() {
        #expect(TodayMorningFlow.prefKey(verdictDate: "2026-09-23") == "today.morning.2026-09-23")
    }
    @Test func restDayHasNoAdjust() {
        #expect(TodayMorningFlow.isRestDay(verdictParts("REST")))
        #expect(TodayMorningFlow.isRestDay(verdictParts("Rest — mobility only")))
        #expect(!TodayMorningFlow.isRestDay(verdictParts("GO — Full Upper")))
        #expect(!TodayMorningFlow.isRestDay(verdictParts(nil)))
    }
}

// W-FIX2 DEV-04 (Toby 2026-09-25) — "start at the gate": the first launch after local midnight
// opens Decide; `-JIForceGate YES` (and `ji://gate`) force it without touching the stored call.
@Suite struct GateLaunchTests {
    @Test func firstLaunchOfTheLocalDayOpensTheGate() {
        #expect(GateLaunch.shouldOpenGate(localDay: "2026-09-25", lastAnsweredLocalDay: "2026-09-24", forced: false))
        #expect(GateLaunch.shouldOpenGate(localDay: "2026-09-25", lastAnsweredLocalDay: nil, forced: false))
    }
    @Test func answeredTodayStaysOnTheDayUnlessForced() {
        #expect(!GateLaunch.shouldOpenGate(localDay: "2026-09-25", lastAnsweredLocalDay: "2026-09-25", forced: false))
        #expect(GateLaunch.shouldOpenGate(localDay: "2026-09-25", lastAnsweredLocalDay: "2026-09-25", forced: true))
    }
    @Test func forceArgumentIsReadFromTheLaunchArguments() {
        #expect(GateLaunch.forcedByArguments(["app", "-JIForceGate", "YES"]))
        #expect(GateLaunch.forcedByArguments(["app", "-JIForceGate", "1"]))
        #expect(!GateLaunch.forcedByArguments(["app", "-JIForceGate", "NO"]))
        #expect(!GateLaunch.forcedByArguments(["app", "-JIForceGate"]))
        #expect(!GateLaunch.forcedByArguments(["app"]))
    }
    @Test func localDayIsTheDeviceCalendarDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        // 2026-09-24T22:30Z = 00:30 on 25 Sep in Zurich: already the new local day.
        let d = Date(timeIntervalSince1970: 1_790_289_000)
        #expect(GateLaunch.localDay(d, calendar: cal) == "2026-09-25")
    }
    @Test func lastAnsweredDayHasItsOwnPrefKey() {
        #expect(GateLaunch.lastAnsweredKey == "today.gate.lastAnsweredLocalDay")
        #expect(GateLaunch.lastAnsweredKey != TodayMorningFlow.prefKey(verdictDate: "2026-09-25"))
    }
}
