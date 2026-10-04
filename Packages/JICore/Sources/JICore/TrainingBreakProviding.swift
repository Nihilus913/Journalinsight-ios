import Foundation

/// W-B91 (Toby 2026-10-04: "B91 pause should be a manual status") — the user's "I'm on a break"
/// toggle on the hub (`plan.training_break`, HT migration 076). While it is on, Decide's Load row
/// reads "Paused" + `since` instead of an ACWR band; the hub never infers a pause.
public struct TrainingBreak: Codable, Sendable, Equatable {
    public var paused: Bool
    /// The first day of the break, "yyyy-MM-dd"; nil when not paused.
    public var since: String?

    public init(paused: Bool, since: String? = nil) {
        self.paused = paused
        self.since = since
    }
}

public protocol TrainingBreakProviding: Sendable {
    /// `GET /api/v1/planning/training-break`.
    func trainingBreak() async throws -> TrainingBreak
    /// `PUT /api/v1/planning/training-break` `{"paused", "since"}` — `since` nil = the hub's today
    /// (on) / ignored (off). Returns the stored state.
    func setTrainingBreak(paused: Bool, since: String?) async throws -> TrainingBreak
}
