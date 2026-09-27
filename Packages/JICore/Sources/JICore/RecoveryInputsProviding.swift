/// B-57 W3 — the recovery score's own hub slice, in its own protocol so the frozen
/// `HealthDataProvider` does not grow (same pattern as `EnergyProviding`). The on-device
/// `HealthKitProvider` does not conform in W3 (B-50): the service then says "No data".
public protocol RecoveryInputsProviding: Sendable {
    /// `GET /api/v1/vitals/recovery-inputs?date=&window_days=` — ascending days ending at `date`;
    /// a day with no reading at all is absent, a missing field is nil.
    func recoveryInputs(date: String, windowDays: Int) async throws -> [RecoveryInputDay]
}
