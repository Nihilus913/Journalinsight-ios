import Foundation

/// `POST /api/v1/vitals/weighin` request body (oracle: `WeighinBody`/`logWeighin` in
/// `mobile/src/data/{types.ts,HubDataProvider.ts}`). Explicit snake_case `CodingKeys`:
/// `HubClient.post`/`.send` encode the outgoing body with a plain `JSONEncoder()` (not
/// `JSON.encoder`'s `.convertToSnakeCase` — see `HubClient.swift`'s doc comment), so this type
/// must already be snake_case on the wire (same convention as `ExerciseUpdate`).
public struct WeighinBody: Codable, Sendable, Equatable {
    public var weightKg: Double
    /// `nil` lets the hub default to today (`app/vitals/router.py`'s `body.date or dt.date.today()`).
    public var date: String?
    public init(weightKg: Double, date: String? = nil) {
        self.weightKg = weightKg; self.date = date
    }
    private enum CodingKeys: String, CodingKey {
        case weightKg = "weight_kg"
        case date
    }
}

/// `POST /api/v1/vitals/weighin` response (oracle: `WeighinResult` in `mobile/src/data/types.ts`).
/// Pushes a weigh-in to Garmin (FIT upload) and verifies it via read-back; idempotent per date.
/// Both upload rejection and a failed read-back verification surface as `HubError.http`/
/// `.yazioAuthExpired` (502) with the hub's own `detail` — never a bare 500 — so this type has no
/// failure-shaped fields of its own.
public struct WeighinResult: Codable, Sendable, Equatable {
    public var status: String
    public var weightKg: Double
    public var date: String
    public var garminConfirmed: Bool
    public init(status: String, weightKg: Double, date: String, garminConfirmed: Bool) {
        self.status = status; self.weightKg = weightKg; self.date = date; self.garminConfirmed = garminConfirmed
    }
}
