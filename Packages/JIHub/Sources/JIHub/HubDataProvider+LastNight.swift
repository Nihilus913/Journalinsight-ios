import Foundation
import JICore

/// W-FIX13 F-7 (B-69): `GET /api/v1/vitals/recovery` → `last_night` (HT `app/vitals/last_night.py`).
/// A one-day window: only `last_night` is read here; the rows come from `recovery(windowDays:)`.
extension HubDataProvider: RecoveryLastNightProviding {
    public func recoveryLastNight() async throws -> RecoveryLastNight? {
        let r: RecoveryReport = try await client.get("/api/v1/vitals/recovery", query: ["window_days": "1"])
        return r.lastNight
    }
}
