import Foundation
import Testing
import JICore
@testable import JIFeatures

/// RG-35: the Sleep card's "Window" tile reads `/vitals/sleep-summary`'s last-night window
/// ("21:13–04:59") instead of always "— not read".
@Suite struct RecoverySleepWindowTests {
    private func noon(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso + "T12:00:00Z")!
    }

    @Test func decodesWindowFromHubJSON() throws {
        let json = #"{"last_night_date":"2026-10-05","last_night_sleep_start_local":"2026-10-04T21:13:41","last_night_sleep_end_local":"2026-10-05T04:59:10","bedtime_consistency_nights":0,"bedtime_consistency_sources":[]}"#
        let s = try JSON.decoder.decode(SleepSummary.self, from: Data(json.utf8))
        #expect(s.lastNightSleepStartLocal == "2026-10-04T21:13:41")
        #expect(recoverySleepWindowText(s, now: noon("2026-10-05")) == "21:13–04:59")
    }

    @Test func missingWindowStaysNotRead() {
        #expect(recoverySleepWindowText(nil) == nil)
        let noWindow = SleepSummary(lastNightDate: "2026-10-05")
        #expect(recoverySleepWindowText(noWindow, now: noon("2026-10-05")) == nil)
    }

    @Test func staleNightIsNotShownAsLastNight() {
        let old = SleepSummary(lastNightDate: "2026-09-28", lastNightSleepStartLocal: "2026-09-27T22:00:00",
                               lastNightSleepEndLocal: "2026-09-28T06:00:00")
        #expect(recoverySleepWindowText(old, now: noon("2026-10-05")) == nil)
    }
}
