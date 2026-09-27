import Foundation
import Testing
@testable import JIFeatures

// W-GUI M1 — More (mockup 08): the Apple Health row says "Connected" only from an arrival time.
@Test func appleHealthRowIsArrivalBased() {
    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!; utc.locale = Locale(identifier: "en_GB")
    let now = Date(timeIntervalSince1970: 1_790_208_000 + 9 * 3600)          // 2026-09-24 09:00 UTC
    let today = Date(timeIntervalSince1970: 1_790_208_000 + 7 * 3600 + 41 * 60)
    let older = Date(timeIntervalSince1970: 1_790_208_000 - 14 * 3600 + 14 * 60)
    #expect(moreAppleHealthText(lastUpload: today, now: now, calendar: utc) == "Connected · last upload 07:41")
    #expect(moreAppleHealthText(lastUpload: older, now: now, calendar: utc) == "Connected · last upload 23 Sep 10:14")
    #expect(moreAppleHealthText(lastUpload: nil, now: now, calendar: utc) == "No data yet")
    #expect(moreMirrorCaption.contains("data arrived"))
    let empty = UserDefaults(suiteName: "wgui.more.test.\(UUID().uuidString)")
    #expect(healthKitLastUploadDate(empty) == nil)
}
