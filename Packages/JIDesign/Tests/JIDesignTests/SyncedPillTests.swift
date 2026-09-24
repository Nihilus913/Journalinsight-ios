import Foundation
import Testing
@testable import JIDesign

struct SyncedPillTests {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.locale = Locale(identifier: "en_GB"); return c }
    private let now = Date(timeIntervalSince1970: 1_790_208_000 + 9 * 3600)        // 2026-09-24 09:00 UTC
    private let sameDay = Date(timeIntervalSince1970: 1_790_208_000 + 7 * 3600 + 41 * 60)   // 07:41
    private let yesterday = Date(timeIntervalSince1970: 1_790_208_000 - 14 * 3600 + 14 * 60) // 23 Sep 10:14

    @Test func todayIsTimeOnly() {
        #expect(syncedPillText(sameDay, label: .synced, now: now, calendar: utc) == "Synced 07:41")
        #expect(syncedPillText(sameDay, label: .lastSynced, now: now, calendar: utc) == "Last synced 07:41")
    }

    @Test func anOlderSyncNamesItsDay() {
        #expect(syncedPillText(yesterday, label: .synced, now: now, calendar: utc) == "Synced 23 Sep 10:14")
    }

    @Test func neverSyncedIsWordedNotBlank() {
        #expect(syncedPillText(nil, label: .synced, now: now, calendar: utc) == "Not synced yet")
    }

    @Test func stalenessBannerOnlyForDataOlderThanADay() {
        #expect(!stalenessBannerVisible(fetchedAt: sameDay, hubReachable: false, now: now))
        #expect(!stalenessBannerVisible(fetchedAt: now.addingTimeInterval(-86_400), hubReachable: false, now: now))
        #expect(stalenessBannerVisible(fetchedAt: now.addingTimeInterval(-86_401), hubReachable: false, now: now))
        #expect(!stalenessBannerVisible(fetchedAt: now.addingTimeInterval(-200_000), hubReachable: true, now: now))
        #expect(!stalenessBannerVisible(fetchedAt: nil, hubReachable: false, now: now))
    }

    @Test @MainActor func renders() {
        expectRenders("SyncedPill", height: 44) { SyncedPill(date: sameDay, now: now, calendar: utc) }
        expectRenders("SyncedPill never", height: 44) { SyncedPill(date: nil, now: now, calendar: utc) }
    }
}
