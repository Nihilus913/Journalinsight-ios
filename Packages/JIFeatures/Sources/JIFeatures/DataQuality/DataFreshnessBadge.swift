import SwiftUI
import JICore
import JIDesign

// MARK: - Formatters (pure, ported from the oracle)

/// E16-14(b) — "Synced Xm/h/d ago", or an honest "Not synced yet" for a missing/invalid timestamp.
/// Port of `mobile/src/lib/dataFreshness.ts`'s `formatSyncFreshness`, boundary for boundary.
/// `now` is injected (never `Date()` inside), so the copy is testable at exact boundaries.
public nonisolated func formatSyncFreshness(_ lastSyncISO: String?, now: Date) -> String {
    guard let lastSyncISO, let then = parseHubTimestamp(lastSyncISO) else { return "Not synced yet" }
    let seconds = now.timeIntervalSince(then)
    if seconds < 60 { return "Synced just now" }
    let minutes = Int(seconds / 60)
    if minutes < 60 { return "Synced \(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "Synced \(hours)h ago" }
    return "Synced \(hours / 24)d ago"
}

/// E16-14(b) — "X/Y days tracked". Completeness, plain and literal: no verdict colour, no
/// judgement (oracle `formatTrackedCompleteness`).
public nonisolated func formatTrackedCompleteness(trackedDays: Int, totalDays: Int) -> String {
    "\(trackedDays)/\(totalDays) days tracked"
}

/// `GET /api/v1/ingestion/status` returns `str(MAX(loaded_at))` — a Postgres timestamp with a
/// space separator and no zone (`"2026-09-11 05:10:00"`), not always an ISO-8601 string, and the
/// oracle's `new Date(...)` accepted both. Tries the strict ISO parser first, then that Postgres
/// shape (read as UTC, the hub's own `loaded_at` zone); anything else is "Not synced yet" rather
/// than a fabricated age (rule 5).
nonisolated func parseHubTimestamp(_ raw: String) -> Date? {
    if let date = try? Date(raw, strategy: .iso8601) { return date }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
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

// MARK: - Badge

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
        return formatTrackedCompleteness(trackedDays: trackedDays, totalDays: totalDays)
    }
}

/// E16-14(b) + E14-D7 / W5b-L1 — the compact freshness/completeness line under Today's header
/// ("Synced 12m ago · 5/7 days tracked"), and the app's real entry into the Data Quality
/// drill-down: tapping it opens `DataQualityView` (oracle `DataFreshnessBadge.tsx:33`,
/// `router.push("/data-quality")`). The push itself is the caller's `.navigationDestination`
/// (`TodayGrid`, same idiom as its Mind tile) — this view only fires `onTap`.
///
/// Neutral/muted throughout — this is a fact, not a verdict, so no verdict colour here (rule 6).
/// A nil `onTap` renders the line without a tap target instead of a row that goes nowhere.
public struct DataFreshnessBadge: View {
    @Environment(\.jiTheme) private var theme
    private let info: DataFreshnessInfo?
    private let now: Date
    private let onTap: (() -> Void)?

    public init(info: DataFreshnessInfo?, now: Date = Date(), onTap: (() -> Void)? = nil) {
        self.info = info
        self.now = now
        self.onTap = onTap
    }

    /// Nil info → neutral label; otherwise the oracle's freshness copy.
    var leadingText: String {
        guard let info else { return "Data quality" }
        return formatSyncFreshness(info.lastSyncISO, now: now)
    }

    var trailingText: String? {
        guard let info else { return "Per-source detail" }
        return info.completenessText
    }

    public var body: some View {
        Button { onTap?() } label: {
            HStack {
                Text(leadingText).jiFont(.micro).foregroundStyle(theme.color(.muted))
                Spacer(minLength: 8)
                if let trailingText {
                    Text(trailingText).jiFont(.micro).foregroundStyle(theme.color(.muted))
                }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(theme.color(.mutedNested))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityLabel("Data quality detail")
        .accessibilityValue(trailingText.map { "\(leadingText), \($0)" } ?? leadingText)
        .accessibilityHint("Opens per-source data quality, freshness and trust")
        .accessibilityIdentifier("today.badge.dataFreshness")
    }
}
