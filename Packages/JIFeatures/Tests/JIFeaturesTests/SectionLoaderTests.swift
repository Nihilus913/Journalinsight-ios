import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// `SyncStatus` has no public memberwise init (JICore, frozen this wave) — build it the same way
/// `TodayViewModelTests.todayRowFallbackMatchesRN` builds a `DailyKpiRow`: decode a small JSON literal.
private func syncStatus(_ lastSync: String?) throws -> SyncStatus {
    let json = lastSync.map { "{\"last_sync\":\"\($0)\"}" } ?? "{}"
    return try JSON.decoder.decode(SyncStatus.self, from: Data(json.utf8))
}

@Test func sectionLoaderSuccessCachesAndReturnsAFreshFetchedAt() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let result = try await SectionLoader.load(key: "test.sync", cache: cache) {
        try syncStatus("2026-09-13T00:00:00Z")
    }
    #expect(result.value?.lastSync == "2026-09-13T00:00:00Z")
    #expect(result.error == nil)
    #expect(result.stale == false)
    #expect(result.fetchedAt != nil)
    #expect(try cache.get("test.sync", as: SyncStatus.self)?.value.lastSync == "2026-09-13T00:00:00Z")
}

@Test func sectionLoaderFallsBackToCacheOnFailureAndTagsItStale() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    try cache.put("test.sync", try syncStatus("2026-09-01T00:00:00Z"))
    let cachedAt = try #require(try cache.fetchedAt("test.sync"))

    let result = try await SectionLoader.load(key: "test.sync", cache: cache) { () async throws -> SyncStatus in
        throw HubError.network("down")
    }
    #expect(result.value?.lastSync == "2026-09-01T00:00:00Z")
    #expect(result.fetchedAt == cachedAt)
    #expect(result.error == .network("down"))
    #expect(result.stale)
}

@Test func sectionLoaderReturnsNilValueAndTheTypedErrorWhenCacheIsAlsoEmpty() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let result = try await SectionLoader.load(key: "test.sync", cache: cache) { () async throws -> SyncStatus in
        throw HubError.network("down")
    }
    #expect(result.value == nil)
    #expect(result.fetchedAt == nil)
    #expect(result.error == .network("down"))
    #expect(result.stale == false)
}

/// PARITY-7: one section's cache warmth (or lack of it) must never leak into a sibling's `fetchedAt` —
/// each key's fallback is looked up independently.
@Test func sectionLoaderFetchedAtIsIndependentPerKey() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    try cache.put("today.gate", try syncStatus("2026-09-01T00:00:00Z"))

    let gate = try await SectionLoader.load(key: "today.gate", cache: cache) { () async throws -> SyncStatus in
        throw HubError.network("down")
    }
    let recovery = try await SectionLoader.load(key: "today.recovery", cache: cache) { () async throws -> SyncStatus in
        throw HubError.network("down")
    }
    #expect(gate.fetchedAt != nil)      // fell back to its own warm cache entry
    #expect(recovery.fetchedAt == nil)  // no cache under this key — stays nil, not borrowed from `gate`
}

/// A cancellation must propagate as-is, not be swallowed as an ordinary section failure — a caller
/// awaiting several sections together (as `TodayViewModel.fetchLive` does via `async let`) relies on
/// seeing the cancellation itself, so it can return to `.idle` instead of reporting a false error
/// (CODE-1's cancellation contract).
@Test func sectionLoaderRethrowsCancellationInsteadOfFallingBackToCache() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    try cache.put("today.gate", try syncStatus("2026-09-01T00:00:00Z"))

    let task = Task {
        try await SectionLoader.load(key: "today.gate", cache: cache) { () async throws -> SyncStatus in
            try await Task.sleep(for: .seconds(30))
            return try syncStatus(nil)
        }
    }
    try await Task.sleep(for: .milliseconds(50))
    task.cancel()
    await #expect(throws: (any Error).self) { try await task.value }
}
