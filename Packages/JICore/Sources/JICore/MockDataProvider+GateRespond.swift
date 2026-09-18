import Foundation

/// W5b-L4 — `MockDataProvider`'s `GateRespondProviding` conformance. `MockDataProvider.swift`
/// itself is frozen this wave (several lanes would collide on it), so this lives in its own
/// extension file, same pattern as `MockDataProvider+KpiTargets.swift`.
///
/// No bundled fixture: both routes are POSTs whose responses are a server-assigned row id
/// (`log_id` / `feel_id`), not a capturable document — there is no `planning_gate_respond.json`
/// among the fixtures of record (`HealthTraining/fixtures/hub-contract/`, read-only from here,
/// and `Fixtures/MANIFEST.sha256` is generated from exactly that directory). So this echoes the
/// posted body back, matching `MockDataProvider+Nutrition.logFood`'s "echo the posted body"
/// convention for previews and happy-path tests; the failure branches are exercised against the
/// real `HubClient` with `StubURLProtocol` (JIHub) and against fakes (JIFeatures).
extension MockDataProvider: GateRespondProviding {
    /// `pdf_requested` mirrors the hub's own rule verbatim (`app/planning/router.py`'s
    /// `gate_respond`: `body.choice in ("y", "override")`).
    public func respondGate(choice: GateChoice, overrideReason: String, windowDays: Int) async throws -> GateRespondResult {
        GateRespondResult(pdfRequested: choice == .yes || choice == .override, logId: 1)
    }

    public func logFeel(feelScore: Int, notes: String, date: String?) async throws -> FeelResult {
        FeelResult(feelId: 1)
    }
}
