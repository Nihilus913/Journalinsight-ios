import SwiftUI
import JICore
import JIDesign

/// `GET /api/v1/ingestion/status` returns `str(MAX(loaded_at))` — a Postgres timestamp with a
/// space separator and no zone (`"2026-09-11 05:10:00"`), not always an ISO-8601 string, and the
/// oracle's `new Date(...)` accepted both. Tries the strict ISO parser first, then that Postgres
/// shape (read as UTC, the hub's own `loaded_at` zone); anything else is "Not synced yet" rather
/// than a fabricated age (rule 5).
nonisolated func parseHubTimestamp(_ raw: String) -> Date? {
    if let date = try? Date(raw, strategy: .iso8601) { return date }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC") // hub instant default, not a day key (F-1)
    // W-FIX1 BUG-23: the hub's `str(timestamptz)` carries a space separator AND an offset
    // ("2026-09-25 10:02:23.725876+02:00", or "+00" / "+0200"), so the zoned shapes come first;
    // an explicit offset wins over the UTC default.
    for format in ["yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX", "yyyy-MM-dd HH:mm:ssXXXXX",
                   "yyyy-MM-dd HH:mm:ss.SSSSSSX", "yyyy-MM-dd HH:mm:ssX",
                   "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
                   "yyyy-MM-dd HH:mm:ss.SSSSSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss"] {
        formatter.dateFormat = format
        if let date = formatter.date(from: raw) { return date }
    }
    return nil
}

/// What the badge line knows. Passed as an Optional so a caller that has no sync/gate data at all
/// (nothing fetched yet) is distinguishable from one that knows the hub has never synced — the
/// former renders a neutral "Data quality" label, the latter the honest "Not synced yet".
public nonisolated struct DataFreshnessInfo: Sendable, Equatable {
    /// `SyncStatus.lastSync` (`GET /api/v1/ingestion/status`).
    public var lastSyncISO: String?
    /// `GateResponse.trackedDays` / `.totalDays` — the same pair WeekStrip's title computes.
    public var trackedDays: Int?
    public var totalDays: Int?
    public init(lastSyncISO: String?, trackedDays: Int? = nil, totalDays: Int? = nil) {
        self.lastSyncISO = lastSyncISO; self.trackedDays = trackedDays; self.totalDays = totalDays
    }

    /// Rule 5: with no tracked/total pair there is nothing honest to say — the line omits the
    /// completeness half rather than printing "0/0 days tracked".
    public var completenessText: String? {
        guard let trackedDays, let totalDays, totalDays > 0 else { return nil }
        return "\(trackedDays)/\(totalDays) days tracked"
    }
}
