#if canImport(HealthKit)
import Foundation

/// Local test double (not shared with JIHubTests' own `StubURLProtocol`): serves one `steps`
/// entry per request, keyed by the `from` query param, so each month chunk produces a
/// distinguishable, deterministic sync id (`steps:<from>`).
final class DynamicStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestedFroms: [String] = []
    /// v2 test seam: the raw `kinds` query value seen on each request, in request order (`nil`
    /// when a request carried no `kinds` param at all) — lets tests assert on the daily-pass vs
    /// dense-pass split (`BackloadClientTests` covers `BackloadClient` itself in isolation; this
    /// is for `HealthKitBackloaderTests`, which drives the real two-fetch-per-chunk call site).
    nonisolated(unsafe) static var requestedKinds: [String?] = []
    /// v2 test seam: when set, this JSON is served verbatim (ignoring `from`/`to`) for every
    /// request instead of the default one-`steps`-entry-per-request body. Reset alongside
    /// `requestedFroms` so one test's override never leaks into the next.
    nonisolated(unsafe) static var customResponseJSON: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let from = comps?.queryItems?.first(where: { $0.name == "from" })?.value ?? "unknown"
        Self.requestedFroms.append(from)
        Self.requestedKinds.append(comps?.queryItems?.first(where: { $0.name == "kinds" })?.value)
        let json = Self.customResponseJSON ?? """
        {"from":"\(from)","to":"\(from)","source":"garmin_api","sleep":[],"rhr":[],"steps":[{"sync_id":"steps:\(from)","date":"\(from)","count":100}],"energy":[],"vo2max":[],"workouts":[]}
        """
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [DynamicStubURLProtocol.self]
        return URLSession(configuration: c)
    }
    static func reset() { requestedFroms = []; requestedKinds = []; customResponseJSON = nil }
}
#endif
