import Foundation
import Testing
@testable import JICore

/// W-FIX13 F-1 fixer: the hub's backload wire dates are hub-local (W2h contract), a fixed zone
/// that does NOT follow the phone. It lives in exactly one place, `DayKey.hubZone`.
@Suite struct HubZoneTests {
    @Test func hubZoneIsTheW2hContractZone() {
        #expect(DayKey.hubZone.identifier == "Europe/Zurich")
    }

    @Test func hubZoneIgnoresThePhoneZone() {
        // 2026-10-04 23:30 in New York = 2026-10-05 05:30 in the hub's zone.
        let ny = TimeZone(identifier: "America/New_York")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = ny
        let t = cal.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 23, minute: 30))!
        #expect(DayKey(date: t, in: ny).iso == "2026-10-04")
        #expect(DayKey(date: t, in: DayKey.hubZone).iso == "2026-10-05")
    }
}
