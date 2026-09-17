import Foundation
import Testing
@testable import LiveActivityPolicyKit

@Suite
struct LiveActivityCapPolicyTests {
    static let start = Date(timeIntervalSince1970: 1_757_000_000)

    @Test
    func freshActivityDoesNotEnd() {
        let now = Self.start.addingTimeInterval(60) // 1 minute in
        #expect(!LiveActivityCapPolicy.shouldEnd(startedAt: Self.start, lastUpdateAt: Self.start, now: now))
    }

    @Test
    func endsAtTheEightHourActiveCap() {
        let justUnder = Self.start.addingTimeInterval(8 * 3600 - 1)
        let atCap = Self.start.addingTimeInterval(8 * 3600)
        #expect(!LiveActivityCapPolicy.shouldEnd(startedAt: Self.start, lastUpdateAt: justUnder, now: justUnder))
        #expect(LiveActivityCapPolicy.shouldEnd(startedAt: Self.start, lastUpdateAt: atCap, now: atCap))
    }

    @Test
    func endsAtTheFourHourStaleCapEvenWithinTheActiveCap() {
        let lastUpdate = Self.start.addingTimeInterval(30 * 60) // updated 30 min after start
        let stillFresh = lastUpdate.addingTimeInterval(4 * 3600 - 1)
        let stale = lastUpdate.addingTimeInterval(4 * 3600)
        #expect(!LiveActivityCapPolicy.shouldEnd(startedAt: Self.start, lastUpdateAt: lastUpdate, now: stillFresh))
        #expect(LiveActivityCapPolicy.shouldEnd(startedAt: Self.start, lastUpdateAt: lastUpdate, now: stale))
        // Sanity: `stale` is still well inside the 8h active cap on its own.
        #expect(stale.timeIntervalSince(Self.start) < 8 * 3600)
    }

    @Test
    func regularUpdatesKeepItAliveUntilTheActiveCap() {
        // A steady stream of updates every hour never trips the stale cap,
        // but the activity still ends once total active time hits 8h.
        var lastUpdate = Self.start
        for hour in 1...8 {
            let now = Self.start.addingTimeInterval(TimeInterval(hour) * 3600)
            let shouldEnd = LiveActivityCapPolicy.shouldEnd(startedAt: Self.start, lastUpdateAt: lastUpdate, now: now)
            if hour < 8 {
                #expect(!shouldEnd, "hour \(hour) should still be alive")
            } else {
                #expect(shouldEnd, "hour \(hour) should hit the active cap")
            }
            lastUpdate = now
        }
    }

    @Test
    func clockSkewNeverEndsRetroactively() {
        let now = Self.start.addingTimeInterval(-10) // now before startedAt — defensive guard
        #expect(!LiveActivityCapPolicy.shouldEnd(startedAt: Self.start, lastUpdateAt: Self.start, now: now))
    }
}
