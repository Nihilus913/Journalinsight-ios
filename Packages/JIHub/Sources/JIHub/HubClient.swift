import Foundation
import JICore

public struct HubClient: Sendable {
    public let config: ConnectionConfig
    private let session: URLSession
    /// The zone sent as `X-JI-TZ` on every request (W-KEYS K5, Toby D1): the hub keys "today" by
    /// the phone's zone. Read per request, so a travel zone change applies without a relaunch.
    /// W-FIX13 F-2: defaults to `DayKey.zone`, the same zone every app day computation uses; the
    /// hub stores the latest value (`app_settings.phone_tz`) for the morning window.
    private let timeZone: @Sendable () -> TimeZone
    public static let timeZoneHeader = "X-JI-TZ"
    /// B-52 p1 (b): the default read-through cache for EVERY `get` (nil = no cache, e.g. tests and
    /// `ConnectionTest`). See `HubReadCache` and `getRead`.
    public let readCache: (any HubReadCache)?
    /// Paths never served from cache: `/health` is the watchdog's reachability probe — answering it
    /// from a stored copy would report a dead hub as alive.
    public static let uncachedPaths: Set<String> = ["/health"]

    public init(config: ConnectionConfig, session: URLSession = HubClient.makeDefaultSession(),
                timeZone: @escaping @Sendable () -> TimeZone = { DayKey.zone },
                readCache: (any HubReadCache)? = nil) {
        self.config = config; self.session = session; self.timeZone = timeZone; self.readCache = readCache
    }

    /// Whether a failed read may be answered from cache: only "the hub is not there" (no
    /// connection, timeout, a proxy 503/504/500). Named hub answers (401, 409, 502 YAZIO, 404, 422…)
    /// are the hub speaking — they are load-bearing UI contracts and are never masked by a copy.
    public static func isOfflineFailure(_ error: Error) -> Bool {
        switch error as? HubError {
        case .network: true
        case .http(let status, _): status == 500 || status == 503 || status == 504
        default: false
        }
    }

    /// Headers every hub request carries: bearer, JSON accept, the phone's zone.
    private func applyCommonHeaders(_ req: inout URLRequest) {
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(timeZone().identifier, forHTTPHeaderField: Self.timeZoneHeader)
    }

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

    /// B-52 p1 (b): every hub GET reads through `readCache` by default. Fresh read → value, bytes
    /// stored, key marked fresh. Offline failure (`isOfflineFailure`) with a stored copy → that copy,
    /// key marked stale in `HubReadStaleness.shared`. No copy (cold cache) or any other failure →
    /// the original error, unchanged.
    public func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try await getRead(path, query: query).value
    }

    /// `get` with provenance (`stale`, `fetchedAt`) for a screen that shows "offline, as of …".
    public func getRead<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> HubRead<T> {
        guard let readCache, !Self.uncachedPaths.contains(path), HubReadPolicy.current == .cacheFallback else {
            let (value, _): (T, Data) = try await fetch(path, query: query)
            return HubRead(value: value, fetchedAt: Date(), stale: false)
        }
        let key = HubReadKey.make(path: path, query: query)
        do {
            let (value, data): (T, Data) = try await fetch(path, query: query)
            readCache.storeRead(key, data)
            HubReadStaleness.shared.markFresh(key)
            return HubRead(value: value, fetchedAt: Date(), stale: false)
        } catch {
            guard Self.isOfflineFailure(error), let hit = readCache.loadRead(key),
                  let value = try? JSON.decoder.decode(T.self, from: hit.data) else { throw error }
            HubReadStaleness.shared.markStale(key, fetchedAt: hit.fetchedAt)
            HubReadTrace.current?.record(key, fetchedAt: hit.fetchedAt)
            return HubRead(value: value, fetchedAt: hit.fetchedAt, stale: true)
        }
    }

    /// The network GET itself: decoded value + the raw bytes it decoded from (what the cache stores).
    private func fetch<T: Decodable>(_ path: String, query: [String: String]) async throws -> (T, Data) {
        var comps = URLComponents(url: config.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 15
        applyCommonHeaders(&req)
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) } catch { throw HubError.network(error.localizedDescription) }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSON.decoder.decode([String: String].self, from: data))?["detail"]
            throw HubError.from(status: status, detail: detail)
        }
        do { return (try JSON.decoder.decode(T.self, from: data), data) } catch { throw HubError.decoding("\(path): \(error)") }
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
        applyCommonHeaders(&req)
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
    /// to decode a body.
    public func delete(_ path: String, query: [String: String] = [:]) async throws {
        var comps = URLComponents(url: config.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 15
        applyCommonHeaders(&req)
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) } catch { throw HubError.network(error.localizedDescription) }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSON.decoder.decode([String: String].self, from: data))?["detail"]
            throw HubError.from(status: status, detail: detail)
        }
    }
}
