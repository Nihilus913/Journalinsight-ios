import Foundation

/// W-B57b (B-62) — the morning-verdict override write, its own protocol per the
/// `GateRespondProviding` / `PlanSessionWeekdayProviding` idiom so `OutboxDrainer` can ask "can this
/// instance deliver a `verdictOverride` row?" without a screen's whole hub slice.
///
/// Distinct from `GateRespondProviding.respondGate`: that answers the WEEKLY nutrition/KPI gate;
/// this rewrites what the MORNING training verdict (`plan.morning_verdict`) means for its date.
public protocol VerdictOverrideProviding: Sendable {
    /// `POST /api/v1/planning/verdict-override` — upsert per `date`; returns the stored row with
    /// the hub-resolved `session`.
    func setVerdictOverride(date: String, choice: VerdictOverrideChoice, reason: String) async throws -> VerdictOverride

    /// `DELETE /api/v1/planning/verdict-override?date=` — undo (204).
    func clearVerdictOverride(date: String) async throws
}
