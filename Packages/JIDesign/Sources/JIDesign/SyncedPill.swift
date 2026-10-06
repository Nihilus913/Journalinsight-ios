import SwiftUI

public nonisolated enum JISyncedLabel: String, Sendable { case synced = "Synced", lastSynced = "Last synced" }

/// B-57 §1: "Synced 07:41" today, "Synced 23 Sep 10:14" for an older sync, "Not synced yet" when
/// there has never been one. Deterministic (calendar in: its locale and time zone pick the clock).
public nonisolated func syncedPillText(_ date: Date?, label: JISyncedLabel, now: Date, calendar: Calendar) -> String {
    guard let date else { return "Not synced yet" }
    let c = calendar.dateComponents([.day, .month], from: date)
    // W-FIX12 F12-2: the one locale short-time formatter (`jiShortTime`), as the offline pill.
    let time = jiShortTime(date, calendar: calendar)
    if calendar.isDate(date, inSameDayAs: now) { return "\(label.rawValue) \(time)" }
    let months = calendar.shortMonthSymbols
    let month = (c.month.map { months[($0 - 1) % months.count] }) ?? ""
    return "\(label.rawValue) \(c.day ?? 0) \(month) \(time)"
}

/// W-GUI F9: an older-than-today sync reads amber ("Offline · last …" in the mockups): a status
/// word, tinted AND worded (the day is in the text). Today = primary text, never = muted.
public nonisolated func syncedPillIsStale(_ date: Date?, now: Date, calendar: Calendar) -> Bool {
    guard let date else { return false }
    return !calendar.isDate(date, inSameDayAs: now)
}

extension EnvironmentValues {
    /// The shell's one sync instant (`TodayViewModel.syncedAt`), injected by `RootTabView` on
    /// every tab stack. `nil` when the shell has not wired it or knows neither time.
    @Entry public var jiSyncedAt: Date? = nil
    /// W-FIX11 H1-15: the screen's hub is unreachable — its sync pill drops the green "today" check.
    @Entry public var jiHubOffline: Bool = false
}

/// W-FIX11 H1-15 (+H2-05): the pill's face. Offline is never the green check, whatever the time.
public nonisolated enum SyncedPillStyle: Sendable, Equatable { case today, older, never, offline }

public nonisolated func syncedPillStyle(_ date: Date?, now: Date, calendar: Calendar, offline: Bool) -> SyncedPillStyle {
    guard let date else { return .never }
    if offline { return .offline }
    return calendar.isDate(date, inSameDayAs: now) ? .today : .older
}

/// W-FIX-P2 RG-23 (B-52): offline shows ONE marker — the screen's amber `OfflinePill`
/// ("Offline · last 07:04"). The sync pill steps aside instead of saying "Synced 07:04" next to it.
public nonisolated func syncedPillVisible(offline: Bool) -> Bool { !offline }

public struct SyncedPill: View {
    let date: Date?, label: JISyncedLabel, now: Date, calendar: Calendar
    @Environment(\.jiTheme) private var theme
    @Environment(\.jiHubOffline) private var offline
    public init(date: Date?, label: JISyncedLabel = .synced, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        self.date = date; self.label = label; self.now = now; self.calendar = calendar
    }
    public var body: some View {
        if syncedPillVisible(offline: offline) { pill }
    }

    @ViewBuilder private var pill: some View {
        let style = syncedPillStyle(date, now: now, calendar: calendar, offline: offline)
        let today = style == .today
        let stale = style == .older || style == .offline
        // W-GUI F9 (report §4.5): one pill format everywhere — 12 pt radius control fill with a
        // hairline rim; older sync amber, today primary, never-synced muted.
        let shape = RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
        Label(syncedPillText(date, label: label, now: now, calendar: calendar),
              systemImage: date == nil ? "exclamationmark.circle" : (today ? "checkmark" : (style == .offline ? "wifi.exclamationmark" : "clock")))
            .jiFont(.footnote, weight: .semibold)
            .foregroundStyle(theme.color(stale ? .reduced : (today ? .text : .muted)))
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, JISpacing.s3).padding(.vertical, 6)
            .background(theme.color(.control), in: shape)
            .overlay(shape.strokeBorder(theme.color(.hairlineOuter), lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("synced-pill")
    }
}
