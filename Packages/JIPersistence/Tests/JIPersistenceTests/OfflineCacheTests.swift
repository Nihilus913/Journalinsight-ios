import Foundation
import Testing
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
