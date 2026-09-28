import Foundation
import Testing
import JICore
@testable import JIFeatures

// W-GUI M6 — Apple Health (47): status from arrival only; tiles never lie about the source.
@Test func arrivalStatusNeverSaysDeclined() {
    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!; utc.locale = Locale(identifier: "en_GB")
    let now = Date(timeIntervalSince1970: 1_790_208_000 + 9 * 3600)
    let today = Date(timeIntervalSince1970: 1_790_208_000 + 7 * 3600 + 41 * 60)
    #expect(healthArrivalStatus(lastUpload: today, now: now, calendar: utc).word == "Connected · 07:41")
    #expect(healthArrivalStatus(lastUpload: nil, now: now, calendar: utc).word == "No data yet")
    let rows = healthReadRowsArrival(capabilities: [.hrvRMSSD], lastUpload: today, now: now)
    #expect(rows.map(\.title) == ["Overnight HRV", "Sleep", "Resting HR", "Workouts", "Food"])
    #expect(rows[0].status.word.hasPrefix("Connected") && rows[3].status.word == "No data yet")
    #expect(!rows.contains { $0.status.word == "Declined" })
}

@Test func computedTilesAreHonestAboutTheSource() {
    let tiles = healthComputedTiles(sleepScore: nil)
    #expect(tiles.map(\.title) == ["Readiness", "Sleep score", "Body Battery"])
    #expect(tiles[0].value == "—" && tiles[0].note == "Calibrating")
    #expect(tiles[1].value == "—" && tiles[1].note == "No data")     // W-FIX7 F7-3: the reason; never "Garmin only"
    #expect(tiles[2].note == "Garmin only")
    #expect(healthComputedTiles(sleepScore: 89)[1].value == "89")
    #expect(healthArrivalCaption.contains("data arrived"))
}
