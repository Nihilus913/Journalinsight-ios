import Foundation
import Testing
import JICore
@testable import JIHub

/// `POST`-path tests for `HubClient.post`. Added as an extension on `HubClientTests`, not a new
/// `@Suite(.serialized)`, per the documented `StubURLProtocol` convention (CONTEXT-IOS-FOUNDATION
/// §5 test convention / `HubDataProviderTests.swift`): two independent serialized suites still
/// interleave on `StubURLProtocol`'s process-global static state in practice.
extension HubClientTests {
    private struct PostBody: Encodable, Equatable { var sleepEnd: String; var qty: Double }
    private struct PostReply: Decodable, Equatable { var status: String; var rowsLoaded: Int? }

    /// `HubClientTests.client()` is `private` to that file, so this extension (a different file)
    /// builds its own equivalent rather than reaching across the file boundary.
    private func postTestClient() -> HubClient {
        HubClient(config: ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k"), session: StubURLProtocol.session())
    }

    @Test func postSendsBearerAndJSONBody() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/ingest/apple-health"] = (200, Data("{\"status\":\"ok\",\"rows_loaded\":3}".utf8))
        let reply: PostReply = try await postTestClient().post("/api/v1/ingest/apple-health", body: PostBody(sleepEnd: "2026-09-17 07:00:00 +0200", qty: 1.5))
        #expect(reply == PostReply(status: "ok", rowsLoaded: 3))
        #expect(StubURLProtocol.lastRequest?.httpMethod == "POST")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func postDoesNotSnakeCaseTheBody() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/ingest/apple-health"] = (200, Data("{\"status\":\"ok\"}".utf8))
        let _: PostReply = try await postTestClient().post("/api/v1/ingest/apple-health", body: PostBody(sleepEnd: "x", qty: 1))
        let bodyData = Self.readBody(StubURLProtocol.lastRequest)
        let obj = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(obj["sleepEnd"] as? String == "x")
        #expect(obj["sleep_end"] == nil)
    }

    /// `URLSession` moves a data task's `httpBody` into `httpBodyStream` before handing the
    /// request to a custom `URLProtocol`, so `request.httpBody` reads back `nil` there — this
    /// reads the stream instead. (`StubURLProtocol` predates this test's need to inspect a
    /// request body, so the workaround lives here rather than in that shared file.)
    private static func readBody(_ request: URLRequest?) -> Data {
        if let body = request?.httpBody { return body }
        guard let stream = request?.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    @Test func postMapsStatusToNamedErrors() async {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/ingest/apple-health"] = (401, Data("{\"detail\":\"bad token\"}".utf8))
        await #expect(throws: HubError.unauthorized) {
            let _: PostReply = try await postTestClient().post("/api/v1/ingest/apple-health", body: PostBody(sleepEnd: "x", qty: 1))
        }
    }

    @Test func postUnmappableBodyIs422HubError() async {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/ingest/apple-health"] = (422, Data("{\"detail\":\"nothing mappable\"}".utf8))
        await #expect(throws: HubError.http(status: 422, detail: "nothing mappable")) {
            let _: PostReply = try await postTestClient().post("/api/v1/ingest/apple-health", body: PostBody(sleepEnd: "x", qty: 1))
        }
    }
}
