import SwiftUI

public nonisolated enum JISyncedLabel: String, Sendable { case synced = "Synced", lastSynced = "Last synced" }

/// B-57 §1: "Synced 07:41" today, "Synced 23 Sep 10:14" for an older sync, "Not synced yet" when
/// there has never been one. Deterministic (calendar in, no `DateFormatter` locale drift).
public nonisolated func syncedPillText(_ date: Date?, label: JISyncedLabel, now: Date, calendar: Calendar) -> String {
    guard let date else { return "Not synced yet" }
    let c = calendar.dateComponents([.day, .month, .hour, .minute], from: date)
    let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
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

public struct SyncedPill: View {
    let date: Date?, label: JISyncedLabel, now: Date, calendar: Calendar
    @Environment(\.jiTheme) private var theme
    public init(date: Date?, label: JISyncedLabel = .synced, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        self.date = date; self.label = label; self.now = now; self.calendar = calendar
    }
    public var body: some View {
        let today = date.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        let stale = syncedPillIsStale(date, now: now, calendar: calendar)
        // W-GUI F9 (report §4.5): one pill format everywhere — 12 pt radius control fill with a
        // hairline rim; older sync amber, today primary, never-synced muted.
        let shape = RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
        Label(syncedPillText(date, label: label, now: now, calendar: calendar),
              systemImage: date == nil ? "exclamationmark.circle" : (today ? "checkmark" : "clock"))
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
