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

public struct SyncedPill: View {
    let date: Date?, label: JISyncedLabel, now: Date, calendar: Calendar
    @Environment(\.jiTheme) private var theme
    public init(date: Date?, label: JISyncedLabel = .synced, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        self.date = date; self.label = label; self.now = now; self.calendar = calendar
    }
    public var body: some View {
        let today = date.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        Label(syncedPillText(date, label: label, now: now, calendar: calendar),
              systemImage: date == nil ? "exclamationmark.circle" : (today ? "checkmark" : "clock"))
            .jiFont(.footnote, weight: .semibold)
            .foregroundStyle(theme.color(today ? .text : .muted))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(theme.color(.surface2), in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("synced-pill")
    }
}
