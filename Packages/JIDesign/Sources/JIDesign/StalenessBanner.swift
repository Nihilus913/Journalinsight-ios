import SwiftUI

/// B-57 §1: the full banner is only for data more than a day old; fresher data carries a `SyncedPill`
/// — and, when the hub is unreachable, the amber `OfflinePill` (W-GUI-2 X2, mockup 57).
public nonisolated func stalenessBannerVisible(fetchedAt: Date?, hubReachable: Bool, now: Date) -> Bool {
    guard !hubReachable, let fetchedAt else { return false }
    return now.timeIntervalSince(fetchedAt) > 86_400
}

/// X2 (57): within a day of the last successful fetch an unreachable hub is a pill, not a banner.
/// Never fetched and unreachable → the pill with no time (there is none to show).
public nonisolated func offlinePillVisible(fetchedAt: Date?, hubReachable: Bool, now: Date) -> Bool {
    guard !hubReachable else { return false }
    guard let fetchedAt else { return true }
    return now.timeIntervalSince(fetchedAt) <= 86_400
}

/// W-FIX11 H1-15 (+H2-05): the time every offline face names — the shell's one sync instant
/// (`jiSyncedAt`, what the sync pills say), else this screen's last fetch. Never three times.
public nonisolated func offlinePillLastDate(syncedAt: Date?, fetchedAt: Date?) -> Date? { syncedAt ?? fetchedAt }

/// "Offline · last 07:41" — the last CALL's time (the hub's, not the phone's), or "Offline" alone.
public nonisolated func offlinePillText(lastTime: String?) -> String {
    lastTime.map { "Offline · last \($0)" } ?? "Offline"
}

public nonisolated func offlinePillAccessibilityLabel(lastTime: String?) -> String {
    lastTime.map { "Offline, last synced \($0)" } ?? "Offline"
}

public nonisolated func stalenessBannerText(lastTime: String) -> String {
    "Showing data from \(lastTime) — hub unreachable"
}

/// The short clock time every staleness face prints ("07:41" / "7:41 AM" per locale).
/// W-FIX12 F12-2: the ONE clock formatter — the sync pill (`syncedPillText`) prints through it too,
/// so offline and synced faces never disagree for the same instant. Root cause of "9:00" vs
/// "09:00": `Date.FormatStyle(time: .shortened)` drops the hour's leading zero in en_GB / de_DE
/// ("9:00") while the locale's short time style is "09:00" (the pill hand-formatted "%02d:%02d").
/// This reads the locale's own short time style; the calendar carries locale and time zone
/// (nil locale = the device's).
public nonisolated func jiShortTime(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
    let f = DateFormatter()
    f.locale = calendar.locale ?? .autoupdatingCurrent
    f.calendar = calendar
    f.timeZone = calendar.timeZone
    f.dateStyle = .none
    f.timeStyle = .short
    return f.string(from: date)
}

/// Mockup 57's title-row pill: amber dot + "Offline · last 07:41". Amber is a STATUS use of
/// `.reduced` (rule 6: worded and tinted), never a verdict.
public struct OfflinePill: View {
    let fetchedAt: Date?
    let now: Date
    @Environment(\.jiTheme) private var theme
    @Environment(\.jiSyncedAt) private var syncedAt
    public init(fetchedAt: Date?, now: Date = Date()) { self.fetchedAt = fetchedAt; self.now = now }

    private var lastTime: String? { offlinePillLastDate(syncedAt: syncedAt, fetchedAt: fetchedAt).map { jiShortTime($0) } }

    public var body: some View {
        HStack(spacing: JISpacing.s1 + 2) {
            Circle().fill(theme.color(.reduced)).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(offlinePillText(lastTime: lastTime)).jiFont(.caption, weight: .semibold).lineLimit(1)
        }
        .foregroundStyle(theme.color(.reduced))
        .padding(.vertical, JISpacing.s1 + 2).padding(.horizontal, JISpacing.s2 + 2)
        .background(theme.color(.surface2), in: Capsule())
        .overlay(Capsule().strokeBorder(theme.color(.hairlineOuter), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(offlinePillAccessibilityLabel(lastTime: lastTime))
        .accessibilityIdentifier("offline-pill")
    }
}

/// PARITY-3: `hubReachable == false` must mean a genuine network outage (`HubError.network`) only —
/// callers must not route a 401 (`HubError.unauthorized`) through this flag, since that is a token
/// problem to be surfaced as an error card with a Connection action, not "stale data, hub unreachable".
///
/// Two faces, never both: the pill under a day of the last fetch (X2 / 57), the banner after.
public struct StalenessBanner: View {
    let fetchedAt: Date?, hubReachable: Bool
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.jiTheme) private var theme
    @Environment(\.jiSyncedAt) private var syncedAt
    public init(fetchedAt: Date?, hubReachable: Bool, now: Date = Date()) { self.fetchedAt = fetchedAt; self.hubReachable = hubReachable; self.now = now }
    public var body: some View {
        if stalenessBannerVisible(fetchedAt: fetchedAt, hubReachable: hubReachable, now: now), let fetchedAt {
            HStack(spacing: JISpacing.s2) {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(theme.color(.reduced))
                    .accessibilityLabel("Hub unreachable")
                Text(stalenessBannerText(lastTime: jiShortTime(offlinePillLastDate(syncedAt: syncedAt, fetchedAt: fetchedAt) ?? fetchedAt)))
                    .jiFont(.footnote).foregroundStyle(theme.color(.text))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(JISpacing.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.color(.surface2), in: RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous).strokeBorder(theme.color(.hairlineOuter), lineWidth: 1))
            .accessibilityIdentifier("staleness-banner")
            .transition(reduceMotion ? AnyTransition.opacity : .move(edge: .top).combined(with: .opacity))
        } else if offlinePillVisible(fetchedAt: fetchedAt, hubReachable: hubReachable, now: now) {
            OfflinePill(fetchedAt: fetchedAt, now: now)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(reduceMotion ? AnyTransition.opacity : .move(edge: .top).combined(with: .opacity))
        }
    }
}
