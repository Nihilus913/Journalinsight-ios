import Foundation
import Testing
@testable import JIDesign

// W-FIX12 F12-2: the offline pill said "9:00" while the synced pill said "09:00" for the same
// instant — two clocks. Both now print through the one locale short-time formatter (`jiShortTime`).
struct Fix12PillTimeTests {
    private func cal(_ locale: String) -> Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.locale = Locale(identifier: locale); return c
    }
    private let nine = Date(timeIntervalSince1970: 1_790_208_000 + 9 * 3600)   // 2026-09-24 09:00 UTC

    @Test func offlineAndSyncedNameNineOClockIdentically() {
        for locale in ["en_GB", "en_US", "de_DE"] {
            let c = cal(locale)
            let time = jiShortTime(nine, calendar: c)
            #expect(syncedPillText(nine, label: .synced, now: nine, calendar: c) == "Synced \(time)")
            #expect(offlinePillText(lastTime: time) == "Offline · last \(time)")
            let older = syncedPillText(nine, label: .synced, now: nine.addingTimeInterval(86_400), calendar: c)
            #expect(older.hasSuffix(" \(time)"))
        }
        #expect(jiShortTime(nine, calendar: cal("en_GB")) == "09:00")
    }
}
