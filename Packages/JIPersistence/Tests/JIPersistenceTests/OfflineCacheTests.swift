import Foundation
import Testing
import JICore
@testable import JIPersistence

private struct Payload: Codable, Equatable { var verdict: String; var n: Int }

@Test func cacheRoundTripsAndStampsTime() throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    #expect(try cache.get("morning", as: Payload.self) == nil)
    try cache.put("morning", Payload(verdict: "GO", n: 1))
    let hit = try #require(try cache.get("morning", as: Payload.self))
    #expect(hit.value == Payload(verdict: "GO", n: 1))
    #expect(abs(hit.fetchedAt.timeIntervalSinceNow) < 5)
}

@Test func putOverwrites() throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    try cache.put("k", Payload(verdict: "A", n: 1))
    try cache.put("k", Payload(verdict: "B", n: 2))
    #expect(try cache.get("k", as: Payload.self)?.value.verdict == "B")
}

/// B-52 p1 (b): the hub read-through store — raw bytes round-trip, own key space, cleared together.
@Test func hubReadCacheRoundTripsRawBytes() throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let key = HubReadKey.make(path: "/api/v1/planning/training-break")
    #expect(cache.loadRead(key) == nil)
    cache.storeRead(key, Data("{\"paused\":true}".utf8))
    let hit = try #require(cache.loadRead(key))
    #expect(String(decoding: hit.data, as: UTF8.self) == "{\"paused\":true}")
    try cache.clear()
    #expect(cache.loadRead(key) == nil)
}
