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
