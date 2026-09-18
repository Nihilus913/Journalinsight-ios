import Foundation

/// W5b-L4 (P-gate-respond) — this lane's own hub slice, added fresh rather than growing the frozen
/// `HealthDataProvider` (same rationale as `KpiTargetsProviding`/`EnergyProviding`): each screen
/// lane owns its own protocol so parallel lanes never collide on one shared interface.
///
/// Oracle: `mobile/src/data/DataProvider.ts:80,82` (`respondGate`/`logFeel`) — same argument
/// order, so a ported call site reads identically. Swift protocol requirements cannot carry
/// default arguments, so conformers spell out RN's `""` / `7` / `nil` defaults themselves.
public protocol GateRespondProviding: Sendable {
    /// `POST /api/v1/planning/gate/respond` — logs the user's answer to the gate recommendation
    /// they were actually shown. The hub re-evaluates the gate for `windowDays` before writing
    /// `plan.decision_log`, so the window the user was viewing is part of the contract.
    func respondGate(choice: GateChoice, overrideReason: String, windowDays: Int) async throws -> GateRespondResult

    /// `POST /api/v1/planning/feel` — a 1–5 session-feel score into `plan.session_feel`.
    /// `date` nil lets the hub use today.
    func logFeel(feelScore: Int, notes: String, date: String?) async throws -> FeelResult
}
