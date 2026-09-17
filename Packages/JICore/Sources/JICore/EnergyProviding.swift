/// W3a-L1 — the Energy tab's own hub slice, added in its own protocol so the frozen
/// `HealthDataProvider` (spec §4.2, CONTEXT-IOS-FOUNDATION.md) never has to grow a case for a
/// screen it doesn't already know about. Mirrors `HealthDataProvider`'s doc-comment style: one
/// method per hub route the Energy tab actually calls.
public protocol EnergyProviding: Sendable {
    /// `GET /api/v1/nutrition/energy?window_days=`
    func energy(windowDays: Int) async throws -> EnergyReport

    /// `GET /api/v1/planning/goals`
    func goals() async throws -> Goals
}
