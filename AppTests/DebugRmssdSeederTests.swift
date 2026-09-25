#if DEBUG
import Foundation
import Testing
@testable import JournalInsight

// W-FIX3 fixer C-h (live record): `-JISeedRMSSD <ms>` writes ONE native-RMSSD sample for last
// night into the simulator's HealthKit, so HKRecoveryAssembler → Today HRV can be proven live.

@Test func rmssdSeedReadsItsLaunchArgument() {
    #expect(DebugRmssdSeeder.requestedValue(["app", "-JISeedRMSSD", "42.5"]) == 42.5)
    #expect(DebugRmssdSeeder.requestedValue(["app"]) == nil)
    #expect(DebugRmssdSeeder.requestedValue(["app", "-JISeedRMSSD"]) == nil)
    #expect(DebugRmssdSeeder.requestedValue(["app", "-JISeedRMSSD", "abc"]) == nil)
    #expect(DebugRmssdSeeder.requestedValue(["app", "-JISeedRMSSD", "0"]) == nil)   // never a 0 ms reading
}

@Test func rmssdSeedIsDatedToLastNightsSleep() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
    let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 13, minute: 5))!
    let at = DebugRmssdSeeder.sampleDate(now: now, calendar: cal)
    let c = cal.dateComponents([.year, .month, .day, .hour], from: at)
    #expect(c.year == 2026 && c.month == 9 && c.day == 25 && c.hour == 3)   // 03:00 → this morning's night
}
#endif
