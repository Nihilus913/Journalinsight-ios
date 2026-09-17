import Foundation
import JICore

public struct HubClient: Sendable {
    public let config: ConnectionConfig
    private let session: URLSession
    public init(config: ConnectionConfig, session: URLSession = HubClient.makeDefaultSession()) { self.config = config; self.session = session }

    /// Ephemeral session: hub responses (sensitive health data) and the bearer auth header
    /// must never be written to CFNetwork's on-disk Cache.db (SEC-1). Callers that pass an
    /// explicit `session:` (e.g. tests) are unaffected.
    ///
    /// Public: referenced from `ConnectionTest.run`'s default argument value too (same SEC-1
    /// requirement), and a default-argument expression must be at least as accessible as the
    /// `public init` it belongs to.
    public static func makeDefaultSession() -> URLSession {
        URLSession(configuration: .ephemeral)
    }

    public func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var comps = URLComponents(url: config.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 15
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) } catch { throw HubError.network(error.localizedDescription) }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSON.decoder.decode([String: String].self, from: data))?["detail"]
            throw HubError.from(status: status, detail: detail)
        }
        do { return try JSON.decoder.decode(T.self, from: data) } catch { throw HubError.decoding("\(path): \(error)") }
    }

    /// POSTs `body` as JSON and decodes the response, mirroring `get`'s status-mapping and error
    /// handling. Encodes with a plain `JSONEncoder()` — deliberately NOT `JSON.encoder` — because
    /// `.convertToSnakeCase` would corrupt a body whose wire contract mixes cases (e.g. W2d's
    /// Health-Auto-Export envelope has camelCase `sleepEnd` alongside snake_case `qty`); callers
    /// with a body type that wants snake-casing should encode it to that shape themselves.
    /// Response decoding still uses `JSON.decoder` (`.convertFromSnakeCase`) like `get`, since
    /// every hub response so far is genuinely snake_case on the wire.
    public func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        try await send("POST", path, body: body)
    }

    /// General write helper for methods beyond GET/POST (PUT/PATCH), mirroring `post`'s exact
    /// request/error/decode shape: plain `JSONEncoder()` for the outgoing body (not `JSON.encoder`,
    /// same rationale as `post`), `JSON.decoder`/`HubError.from` on the way back, same SEC-1
    /// ephemeral-session discipline. `body` is optional so a bodyless write can still decode a
    /// response via the same status-mapping path as `delete` (`delete` has no response body, so
    /// it doesn't call this).
    public func send<B: Encodable, T: Decodable>(_ method: String, _ path: String, body: B?) async throws -> T {
        var req = URLRequest(url: config.baseURL.appending(path: path))
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do { req.httpBody = try JSONEncoder().encode(body) } catch { throw HubError.decoding("\(path): encode \(error)") }
        }
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) } catch { throw HubError.network(error.localizedDescription) }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSON.decoder.decode([String: String].self, from: data))?["detail"]
            throw HubError.from(status: status, detail: detail)
        }
        do { return try JSON.decoder.decode(T.self, from: data) } catch { throw HubError.decoding("\(path): \(error)") }
    }

    /// DELETE with no response body — same request/error mapping as `send`, but doesn't attempt
    /// to decode a body (mirrors `HubDataProvider+Nutrition.swift`'s pre-L0 `deleteLogItem`, which
    /// this seam fix supersedes with a shared, non-`Mirror`-based helper).
    public func delete(_ path: String, query: [String: String] = [:]) async throws {
        var comps = URLComponents(url: config.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 15
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) } catch { throw HubError.network(error.localizedDescription) }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSON.decoder.decode([String: String].self, from: data))?["detail"]
            throw HubError.from(status: status, detail: detail)
        }
    }
}
