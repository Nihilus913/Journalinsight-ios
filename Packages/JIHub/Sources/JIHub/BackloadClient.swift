import Foundation
import JICore

/// Fetches the W2h backload contract from the hub. Range is capped at 92 days server-side (422
/// past that) — callers (JIHealthKit's month chunker) keep every request to one calendar month.
public struct BackloadClient: Sendable {
    private let hub: HubClient
    public init(hub: HubClient) { self.hub = hub }

    // Computed, not stored: `DateFormatter` is not `Sendable` (same reasoning as `JSON.decoder`).
    private static var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "Europe/Zurich")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// `kinds`: the contract v2 `kinds` CSV filter (see `docs/waves/cards/W2i.md`). `nil`/empty
    /// omits the query param entirely, which the hub treats as its `DAILY_KINDS` default — so a
    /// caller that wants the v2 dense series (heart_rate, respiration, spo2, hrv_readings,
    /// step_buckets, stages) MUST pass them explicitly; the hub never sends them unasked
    /// (`app/vitals/backload.py:parse_kinds`). `BackloadMonthChunker.dailyPassKinds` /
    /// `.densePassKinds` are the two sets `HealthKitBackloader` actually calls this with.
    public func fetch(from: Date, to: Date, kinds: Set<String>? = nil) async throws -> BackloadResponseDTO {
        var query = [
            "from": Self.dayFormatter.string(from: from),
            "to": Self.dayFormatter.string(from: to),
        ]
        if let kinds, !kinds.isEmpty {
            query["kinds"] = kinds.sorted().joined(separator: ",")
        }
        return try await hub.get("/api/v1/vitals/backload", query: query)
    }
}
