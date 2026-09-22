import Foundation

/// The one hub write B-52 moves behind the `Outbox`: "this plan session is trained on this
/// weekday" (`PUT /api/v1/planning/plan-sessions/{id}`).
///
/// It exists as its own protocol — next to `WeighInProviding` / `GateRespondProviding`, and NOT
/// as a reuse of `TrainingProviding` — for the same reason those two do: `OutboxDrainer` must be
/// able to ask "can this app instance deliver a row of this kind?" without dragging a screen's
/// whole hub slice (day detail, exercise list, lift PATCH) into a component that only replays
/// writes. A provider that cannot deliver simply doesn't conform, and its rows stay queued
/// instead of being attempted against nothing.
public protocol PlanSessionWeekdayProviding: Sendable {
    /// `PUT /api/v1/planning/plan-sessions/{id}` — Mon = 0 … Sun = 6, `nil` clears the assignment.
    func updatePlanSessionWeekday(sessionId: Int, weekday: Int?) async throws -> PlanSessionOut
}

/// The `Outbox` payload for a `"plan_weekday"` row.
///
/// `sessionName` is not needed to replay the PUT — it is carried so the queued row can still be
/// *described* (and the optimistic plan rows re-matched) by a later launch that has no live plan
/// list yet, which is exactly the offline case this row exists for. camelCase on purpose: this is
/// the outbox's own storage format, encoded with a plain `JSONEncoder()`, never a hub wire body.
public struct PlanWeekdayBody: Codable, Sendable, Equatable {
    public var sessionId: Int
    public var sessionName: String
    public var weekday: Int?
    public init(sessionId: Int, sessionName: String, weekday: Int?) {
        self.sessionId = sessionId; self.sessionName = sessionName; self.weekday = weekday
    }
}
