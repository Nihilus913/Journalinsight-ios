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

    public func fetch(from: Date, to: Date) async throws -> BackloadResponseDTO {
        try await hub.get("/api/v1/vitals/backload", query: [
            "from": Self.dayFormatter.string(from: from),
            "to": Self.dayFormatter.string(from: to),
        ])
    }
}
