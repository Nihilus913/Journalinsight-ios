import Foundation
import Testing
@testable import JIFeatures

// W-FIX11 H2-18 (bug hunt 2026-10-01): Settings › Sync & hub said "Last sync: 2026-10-01
// 09:00:12.485395+02:00." The hub's stamp reads as a local day and time.

@Test func hubLastSyncReadsAsDayAndTime() {
    let zurich = TimeZone(identifier: "Europe/Zurich")!
    let now = ISO8601DateFormatter().date(from: "2026-10-01T16:00:00Z")!
    #expect(hubLastSyncText("2026-10-01 09:00:12.485395+02:00", now: now, timeZone: zurich) == "today 09:00")
    #expect(hubLastSyncText("2026-09-30T21:15:00+02:00", now: now, timeZone: zurich) == "yesterday 21:15")
    #expect(hubLastSyncText("2026-09-24 08:00:00+02:00", now: now, timeZone: zurich) == "24 Sep 08:00")
    #expect(hubLastSyncText(nil, now: now, timeZone: zurich) == "never")
    #expect(hubLastSyncText("garbage", now: now, timeZone: zurich) == "garbage")
}
