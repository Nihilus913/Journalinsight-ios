import Foundation

/// W5b-L4 — `MockDataProvider`'s `GateRespondProviding` conformance. `MockDataProvider.swift`
/// itself is frozen this wave (several lanes would collide on it), so this lives in its own
/// extension file, same pattern as `MockDataProvider+KpiTargets.swift`.
///
/// W-B29 R-2: serves the write-path fixtures of record — `planning_gate_respond.json` /
/// `planning_feel.json`, each `{request, response}` captured from a throwaway hub by
/// `HealthTraining/scripts/parity/capture_hub_fixtures.py --writes` and synced by
/// `sync_fixtures.py` — through the shared `fixtureURL(named:)` lookup. The ids (`log_id` /
/// `feel_id`) are the captured ones; failure branches are exercised against the real
/// `HubClient` with `StubURLProtocol` (JIHub) and against fakes (JIFeatures).
extension MockDataProvider: GateRespondProviding {
    /// `log_id` comes from the fixture; `pdf_requested` mirrors the hub's own rule verbatim
    /// (`app/planning/router.py`'s `gate_respond`: `body.choice in ("y", "override")`), which
    /// the fixture itself records for its `N` request (false).
    public func respondGate(choice: GateChoice, overrideReason: String, windowDays: Int) async throws -> GateRespondResult {
        let captured = try Self.writeFixtureResponse("planning_gate_respond", as: GateRespondResult.self)
        return GateRespondResult(pdfRequested: choice == .yes || choice == .override, logId: captured.logId)
    }

    public func logFeel(feelScore: Int, notes: String, date: String?) async throws -> FeelResult {
        try Self.writeFixtureResponse("planning_feel", as: FeelResult.self)
    }

    /// Decodes the `response` half of a `{request, response}` write fixture.
    private static func writeFixtureResponse<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        guard let url = Self.fixtureURL(named: name) else { throw HubError.decoding("missing fixture \(name)") }
        guard let doc = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              let response = doc["response"]
        else { throw HubError.decoding("fixture \(name) has no response") }
        return try JSON.decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: response))
    }
}
