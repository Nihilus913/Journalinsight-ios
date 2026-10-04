import Foundation
import JICore

/// Fetches the W2h backload contract from the hub. Range is capped at 92 days server-side (422
/// past that) — callers (JIHealthKit's month chunker) keep every request to one calendar month.
public struct BackloadClient: Sendable {
    private let hub: HubClient
    public init(hub: HubClient) { self.hub = hub }

    /// The backload contract's day boundary (W2h): the chunker cuts hub-zone months
    /// (`DayKey.hubZone`), so the range is keyed in the hub's zone, not the phone's.
    private static var zone: TimeZone { DayKey.hubZone }

    /// `kinds`: the contract v2 `kinds` CSV filter (see `docs/waves/cards/W2i.md`). `nil`/empty
    /// omits the query param entirely, which the hub treats as its `DAILY_KINDS` default — so a
    /// caller that wants the v2 dense series (heart_rate, respiration, spo2, hrv_readings,
    /// step_buckets, stages) MUST pass them explicitly; the hub never sends them unasked
    /// (`app/vitals/backload.py:parse_kinds`). `BackloadMonthChunker.dailyPassKinds` /
    /// `.densePassKinds` are the two sets `HealthKitBackloader` actually calls this with.
    public func fetch(from: Date, to: Date, kinds: Set<String>? = nil) async throws -> BackloadResponseDTO {
        var query = [
            "from": DayKey(date: from, in: Self.zone).iso,
            "to": DayKey(date: to, in: Self.zone).iso,
        ]
        if let kinds, !kinds.isEmpty {
            query["kinds"] = kinds.sorted().joined(separator: ",")
        }
        return try await hub.get("/api/v1/vitals/backload", query: query)
    }
}
