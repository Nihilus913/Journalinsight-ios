import Foundation

/// Watchdog-local test double, deliberately NOT `StubURLProtocol` (JIHubTests' path-keyed stub):
/// the watchdog suite needs to flip `/health` between healthy, non-200 and *transport failure*
/// (the timeout case) between awaits in a single test, and sharing `StubURLProtocol`'s
/// process-global `responses` with `HubClientTests`' serialized suite is exactly the cross-suite
/// race that suite's own header warns about. Own class, own statics.
final class WatchdogStubURLProtocol: URLProtocol, @unchecked Sendable { // @unchecked: statics guarded by the serialized watchdog suite
    enum Behaviour: Sendable {
        /// 200 + a valid `HealthResponse` body.
        case ok
        /// A transport-level failure — what a timeout against a sleeping Mac produces.
        case timeout
        /// Any non-200 status (hub up but not serving).
        case status(Int)
    }

    nonisolated(unsafe) static var behaviour: Behaviour = .ok
    nonisolated(unsafe) static var requestedPaths: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestedPaths.append(request.url!.path)
        switch Self.behaviour {
        case .timeout:
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
        case .ok:
            respond(status: 200, body: #"{"status":"ok"}"#)
        case .status(let code):
            respond(status: code, body: #"{"detail":"nope"}"#)
        }
    }

    private func respond(status: Int, body: String) {
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [WatchdogStubURLProtocol.self]
        return URLSession(configuration: c)
    }

    static func reset() {
        behaviour = .ok
        requestedPaths = []
    }
}
