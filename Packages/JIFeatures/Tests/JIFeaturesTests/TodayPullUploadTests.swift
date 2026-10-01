import Testing
import Foundation
import JICore
import JIPersistence
@testable import JIFeatures

/// Toby 2026-10-01: pull-to-refresh on Today uploads Apple Health before it reloads.
@Suite struct TodayPullUploadTests {
    @Test @MainActor func pullToRefreshUploadsHealthBeforeReloading() async throws {
        let m = TodayViewModel(provider: MockDataProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()))
        var order: [String] = []
        m.uploadBeforeRefresh = { order.append("upload") }
        await m.refresh()
        order.append("reloaded")
        #expect(order == ["upload", "reloaded"])
    }

    @Test @MainActor func withoutAnUploaderRefreshStillReloads() async throws {
        let m = TodayViewModel(provider: MockDataProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()))
        await m.refresh() // no hook set → no crash, plain reload
        #expect(m.uploadBeforeRefresh == nil)
    }
}
