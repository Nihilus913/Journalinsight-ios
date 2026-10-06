import Testing
import Foundation
import JICore
@testable import JIFeatures

/// W-FIX-P3 RG-41: the Today "Updated hh:mm" pill — shown only when the hub says core was
/// rewritten after the card's snapshot (`updated_since_verdict`), with `core_updated_at`'s time.
@Suite struct FixP3L8UpdatedPillTests {
    private let utc = TimeZone(identifier: "UTC")!

    @Test func pillShowsUpdatedTimeWhenCoreIsNewer() {
        #expect(decideUpdatedPillText(coreUpdatedAt: "2026-10-06T13:14:07.123456+00:00",
                                      updatedSinceVerdict: true, timeZone: utc) == "Updated 13:14")
    }

    @Test func noPillOtherwise() {
        #expect(decideUpdatedPillText(coreUpdatedAt: "2026-10-06T13:14:00+00:00", updatedSinceVerdict: false, timeZone: utc) == nil)
        #expect(decideUpdatedPillText(coreUpdatedAt: "2026-10-06T13:14:00+00:00", updatedSinceVerdict: nil, timeZone: utc) == nil)
        #expect(decideUpdatedPillText(coreUpdatedAt: nil, updatedSinceVerdict: true, timeZone: utc) == nil)
    }

    @Test func morningDecodesTheHubFields() throws {
        let json = #"{"carb_watch_floor": 150, "core_updated_at": "2026-10-06T13:14:00+00:00", "updated_since_verdict": true}"#
        let m = try JSON.decoder.decode(MorningResponse.self, from: Data(json.utf8))
        #expect(m.coreUpdatedAt == "2026-10-06T13:14:00+00:00")
        #expect(m.updatedSinceVerdict == true)
        let old = try JSON.decoder.decode(MorningResponse.self, from: Data(#"{"carb_watch_floor": 150}"#.utf8))
        #expect(old.coreUpdatedAt == nil && old.updatedSinceVerdict == nil)
    }
}
