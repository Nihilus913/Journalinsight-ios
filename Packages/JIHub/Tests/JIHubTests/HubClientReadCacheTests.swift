import Foundation
import Synchronization
import Testing
import JICore
@testable import JIHub

/// B-52 p1 (b): every hub GET reads through `HubReadCache` by default.
final class MemoryReadCache: HubReadCache {
    private let rows = Mutex<[String: (Data, Date)]>([:])
    func loadRead(_ key: String) -> (data: Data, fetchedAt: Date)? { rows.withLock { $0[key].map { ($0.0, $0.1) } } }
    func storeRead(_ key: String, _ data: Data) { rows.withLock { $0[key] = (data, Date()) } }
    var keys: [String] { rows.withLock { $0.keys.sorted() } }
}

extension HubClientTests {
    private func cachedClient(_ cache: MemoryReadCache) -> HubClient {
        HubClient(config: ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k"),
                  session: StubURLProtocol.session(), readCache: cache)
    }
    private static let statusPath = "/api/v1/ingestion/status"
    private static let statusBody = Data("{\"last_sync\":\"2026-10-04T05:10:00\"}".utf8)

    @Test func b52_readKeyIsPerRouteAndSortedArgs() {
        #expect(HubReadKey.make(path: "/a") == "hub:GET /a")
        #expect(HubReadKey.make(path: "/a", query: ["z": "1", "b": "2"]) == "hub:GET /a?b=2&z=1")
    }

    @Test func b52_freshReadIsStoredAndMarkedFresh() async throws {
        let cache = MemoryReadCache()
        StubURLProtocol.responses[Self.statusPath] = (200, Self.statusBody)
        let read: HubRead<SyncStatus> = try await cachedClient(cache).getRead(Self.statusPath)
        #expect(read.stale == false)
        #expect(read.value.lastSync == "2026-10-04T05:10:00")
        #expect(cache.keys == ["hub:GET \(Self.statusPath)"])
        #expect(!HubReadStaleness.shared.isStale(path: Self.statusPath))
    }

    @Test func b52_hubDownServesLastCopyFlaggedStale() async throws {
        let cache = MemoryReadCache()
        let client = cachedClient(cache)
        StubURLProtocol.responses[Self.statusPath] = (200, Self.statusBody)
        let _: SyncStatus = try await client.get(Self.statusPath)
        StubURLProtocol.responses[Self.statusPath] = (503, Data("{\"detail\":\"down\"}".utf8))
        let (value, staleSince) = try await HubReadTrace.collect { () async throws -> SyncStatus in
            try await client.get(Self.statusPath)
        }
        #expect(value.lastSync == "2026-10-04T05:10:00")
        #expect(staleSince != nil)
        #expect(HubReadStaleness.shared.isStale(path: Self.statusPath))
        // hub back → fresh again, stale mark cleared
        StubURLProtocol.responses[Self.statusPath] = (200, Self.statusBody)
        let read: HubRead<SyncStatus> = try await client.getRead(Self.statusPath)
        #expect(!read.stale)
        #expect(!HubReadStaleness.shared.isStale(path: Self.statusPath))
    }

    @Test func b52_coldCacheStillThrows() async {
        StubURLProtocol.responses[Self.statusPath] = (503, Data("{\"detail\":\"down\"}".utf8))
        await #expect(throws: HubError.http(status: 503, detail: "down")) {
            let _: SyncStatus = try await self.cachedClient(MemoryReadCache()).get(Self.statusPath)
        }
    }

    @Test func b52_namedHubAnswersAreNeverMasked() async throws {
        let cache = MemoryReadCache()
        let client = cachedClient(cache)
        StubURLProtocol.responses[Self.statusPath] = (200, Self.statusBody)
        let _: SyncStatus = try await client.get(Self.statusPath)
        StubURLProtocol.responses[Self.statusPath] = (401, Data("{\"detail\":\"bad\"}".utf8))
        await #expect(throws: HubError.unauthorized) { let _: SyncStatus = try await client.get(Self.statusPath) }
        StubURLProtocol.responses[Self.statusPath] = (502, Data("{\"detail\":\"YAZIO\"}".utf8))
        await #expect(throws: HubError.yazioAuthExpired(detail: "YAZIO")) { let _: SyncStatus = try await client.get(Self.statusPath) }
        #expect(HubClient.isOfflineFailure(HubError.network("offline")))
        #expect(!HubClient.isOfflineFailure(HubError.http(status: 404, detail: nil)))
    }

    @Test func b52_networkOnlyPolicyAndHealthBypassTheCache() async throws {
        let cache = MemoryReadCache()
        let client = cachedClient(cache)
        StubURLProtocol.responses[Self.statusPath] = (200, Self.statusBody)
        let _: SyncStatus = try await client.get(Self.statusPath)
        StubURLProtocol.responses[Self.statusPath] = (503, Data("{\"detail\":\"down\"}".utf8))
        await #expect(throws: HubError.self) {
            try await HubReadPolicy.$current.withValue(.networkOnly) {
                let _: SyncStatus = try await client.get(Self.statusPath)
            }
        }
        StubURLProtocol.responses["/health"] = (200, Data("{\"status\":\"ok\"}".utf8))
        _ = try? await HubDataProvider(client: client).health()
        #expect(!cache.keys.contains("hub:GET /health"))
    }
}
