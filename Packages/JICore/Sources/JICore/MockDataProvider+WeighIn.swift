import Foundation

/// Previews + tests only, same contract as `MockDataProvider`'s own methods (frozen file — this
/// conformance lives here instead, per the Data seam). No mock hub to POST against — resolves
/// immediately as a successful, Garmin-confirmed write, mirroring `MockDataProvider+Training`'s
/// no-op `updateExercise`.
extension MockDataProvider: WeighInProviding {
    public func logWeighin(weightKg: Double, date: String?) async throws -> WeighinResult {
        WeighinResult(status: "ok", weightKg: weightKg, date: date ?? Self.mockToday(), garminConfirmed: true)
    }

    /// A plain device-local `YYYY-MM-DD` stamp for the mock's own "today" default — never used by
    /// the real hub path, which always sends the caller's date (or lets the hub itself default).
    private static func mockToday() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }
}
