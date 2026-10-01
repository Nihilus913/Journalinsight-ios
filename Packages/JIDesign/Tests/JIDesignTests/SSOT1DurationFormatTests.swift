import Testing
@testable import JIDesign

// W-SSOT-1 SS-6 (audit 01-P9): one DurationFormat for the h/m, clock and minute strings that were
// written out inline (SleepCard, RecoveryTiles, WorkoutFormat, SessionCoach, InsightsCard).
@Test func hoursMinutesTruncatesLikeTheSleepCard() {
    #expect(DurationFormat.hoursMinutes(seconds: 26_640) == "7h 24m")
    #expect(DurationFormat.hoursMinutes(seconds: 3_659) == "1h 0m")
}

@Test func hoursPaddedMinutesRoundsToTheMinute() {
    #expect(DurationFormat.hoursPaddedMinutes(seconds: 26_640) == "7 h 24")
    #expect(DurationFormat.hoursPaddedMinutes(seconds: 3_630) == "1 h 01")   // 60.5 min rounds up
    #expect(DurationFormat.hoursPaddedMinutes(seconds: 3_540) == "0 h 59")
}

@Test func clockIsMinutesColonPaddedSeconds() {
    #expect(DurationFormat.clock(seconds: 600) == "10:00")
    #expect(DurationFormat.clock(seconds: 45) == "0:45")
    #expect(DurationFormat.clock(seconds: 3_725) == "62:05")
}

@Test func minutesFloors() {
    #expect(DurationFormat.minutes(seconds: 119) == "1 min")
    #expect(DurationFormat.minutes(seconds: 0) == "0 min")
}
