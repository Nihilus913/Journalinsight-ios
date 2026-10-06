import Foundation
import Testing
@testable import JIFeatures

/// RG-56 (B-105): after Adjust -> Rest the hero kicker shows the user's adjust time, not the hub's
/// compute time.
@Suite struct RG56AdjustCallTimeTests {
    static let utc = TimeZone(identifier: "UTC")!

    @Test func overrideShowsTheUsersTime() {
        let hub = decideCallTime("2026-10-05T05:08:00+00:00", timeZone: Self.utc)
        let mine = decideCallTime("2026-10-05T13:25:41.123456+00:00", timeZone: Self.utc)
        #expect(mine == "13:25")
        #expect(decideCallHeader(verdictDate: "2026-10-05", isStale: false, today: "2026-10-05", callTime: hub,
                                 overridden: true, overrideTime: mine) == "YOUR CALL · 13:25")
        #expect(decideCallHeader(verdictDate: "2026-10-05", isStale: false, today: "2026-10-05", callTime: hub)
                == "YOUR CALL FOR TODAY · 05:08")
    }

    @Test func queuedOverrideHasNoHubTime() {
        #expect(decideCallHeader(verdictDate: "2026-10-05", isStale: false, today: "2026-10-05", callTime: "05:08",
                                 overridden: true, overrideTime: nil) == "YOUR CALL")
    }

    @Test func aStaleCallStaysLastCall() {
        #expect(decideCallHeader(verdictDate: "2026-10-04", isStale: false, today: "2026-10-05", callTime: "05:08",
                                 overridden: true, overrideTime: "13:25") == "LAST CALL · SUN, OCT 4")
    }
}
