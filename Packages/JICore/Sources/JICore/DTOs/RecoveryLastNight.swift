import Foundation

/// W-FIX13 F-7 (B-69): `/vitals/recovery`'s `last_night` — the ONE night the Today vitals tile
/// (HRV, RHR, as-of) and the readiness ring show: the newest night with HRV or RHR, Apple
/// (dso 4) before Garmin (dso 2) on the same date, every value from that night and source.
/// `readiness` is nil while the Apple recovery score is calibrating (never another night's).
public struct RecoveryLastNight: Codable, Sendable, Equatable {
    public var date: String
    public var source: String
    public var dsoKey: Int
    public var hrvMs: Double?
    public var rhrBpm: Double?
    public var readiness: Double?
    /// "ok" | "calibrating" | "missing"
    public var readinessStatus: String

    public init(date: String, source: String, dsoKey: Int, hrvMs: Double?, rhrBpm: Double?, readiness: Double?, readinessStatus: String) {
        self.date = date; self.source = source; self.dsoKey = dsoKey; self.hrvMs = hrvMs; self.rhrBpm = rhrBpm
        self.readiness = readiness; self.readinessStatus = readinessStatus
    }
}

/// A provider that serves `last_night` (the hub). An older hub answers nil — the Today tiles then
/// keep reading the recovery rows.
public protocol RecoveryLastNightProviding: Sendable {
    /// `GET /api/v1/vitals/recovery` → `.last_night`
    func recoveryLastNight() async throws -> RecoveryLastNight?
}
