import Foundation

/// W3b-L4 (P-weigh-in) — this screen's own protocol, added fresh this wave rather than growing
/// the frozen `HealthDataProvider` (same Data-seam convention as W3a's `TrainingProviding`/
/// `NutritionProviding`/`EnergyProviding`: `HealthDataProvider`/`HubDataProvider`/
/// `MockDataProvider` are frozen; each screen lane adds its own protocol in a new file instead).
public protocol WeighInProviding: Sendable {
    /// `POST /api/v1/vitals/weighin` (E3-11, `app/vitals/router.py`) — pushes a weigh-in to Garmin
    /// and verifies it via read-back. `date == nil` lets the hub default to today. Both upload
    /// rejection and a failed read-back verification surface as a named `HubError` (502) whose
    /// `detail` is the user-facing explanation (never a bare 500) — CLAUDE.md rule 5 also means the
    /// entered weight itself must never be coerced to 0 before reaching this call.
    func logWeighin(weightKg: Double, date: String?) async throws -> WeighinResult
}
