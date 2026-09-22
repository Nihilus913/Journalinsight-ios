import SwiftUI
import JICore
import JIDesign

/// Trained/not-trained status for one `DailyKpiRow`, keyed off `kcal_burned_active` (oracle:
/// `trainingDayStatus` in `TrainingDayStrip.tsx`) — a proxy for "trained that day" already present
/// on every gate row, rather than a separate per-date activities fetch just to color 7 dots.
nonisolated public enum TrainingDayStatus: Equatable, Sendable { case future, neutral, good, miss }

/// Same 300-kcal floor as the RN oracle (`SESSION_KCAL_FLOOR`) — a UX judgment call on data
/// already in hand, not a literature-grounded figure.
nonisolated public let sessionKcalFloor: Double = 300

nonisolated public func trainingDayStatus(kcalBurnedActive: Double?, isFuture: Bool) -> TrainingDayStatus {
    if isFuture { return .future }
    guard let kcalBurnedActive else { return .neutral } // not synced yet — no judgment (rule 5)
    return kcalBurnedActive >= sessionKcalFloor ? .good : .miss
}

/// The gregorian/UTC calendar every ISO-date helper on this screen shares — the hub's dates are
/// UTC day keys, so `Calendar.current` would shift a day either side of midnight.
nonisolated let trainingStripCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC") ?? .current
    return c
}()

nonisolated func trainingStripDate(_ iso: String) -> Date? {
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return trainingStripCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
}

nonisolated func trainingStripISO(_ date: Date) -> String {
    let c = trainingStripCalendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

/// Top-of-screen day navigator (oracle: `TrainingDayStrip.tsx`). Reads `gate.daily` — already
/// fetched for `GateDetailCard` — rather than firing a separate request. B-33 §2b.4: renders as
/// the Fitness calendar strip (`WeekStrip`), so the day chips, today's fill and the activity ring
/// come from JIDesign instead of a bespoke horizontal `ScrollView`.
public struct TrainingDayStrip: View {
    /// B-46 device feedback 8 (ROOT CAUSE, reproduced on the iPhone 17 Pro sim against the live
    /// hub — `/tmp/w-b46/l1/repro-02-training.png`): `WeekStrip` lays its chips out in a plain
    /// `HStack`, each chip a fixed `chipSize` circle (36–44 pt). It is built for *seven* days;
    /// `gate.daily` carries however many the hub has cached (11 on Toby's device, 8 today), so
    /// 11 × 36 pt + spacing exceeded the 393-pt viewport, the strip's intrinsic width became the
    /// `ScrollView` content width, and EVERY card on Training was pushed off the leading edge
    /// with a black gutter on the right. The window is the last seven rows, oldest → newest, so
    /// the strip reads chronologically (the hub returns newest-first) and can never over-run the
    /// viewport regardless of how many days the hub sends.
    nonisolated static let stripDayCount = 7

    nonisolated static func stripWindow(_ daily: [DailyKpiRow]) -> [DailyKpiRow] {
        let chronological = daily.sorted { $0.date < $1.date }
        return Array(chronological.suffix(stripDayCount))
    }

    let daily: [DailyKpiRow]
    let selectedDate: String
    let today: String
    let onSelect: (String) -> Void
    @Environment(\.jiTheme) private var theme

    public init(daily: [DailyKpiRow], selectedDate: String, today: String = String(Date().ISO8601Format().prefix(10)), onSelect: @escaping (String) -> Void) {
        self.daily = daily; self.selectedDate = selectedDate; self.today = today; self.onSelect = onSelect
    }

    private func status(_ row: DailyKpiRow) -> TrainingDayStatus {
        trainingDayStatus(kcalBurnedActive: row.values["kcal_burned_active"] ?? nil, isFuture: row.date > today)
    }

    private var windowed: [DailyKpiRow] { Self.stripWindow(daily) }
    private var trainedCount: Int { windowed.filter { status($0) == .good }.count }

    private var days: [WeekStripDay] {
        let symbols = trainingStripCalendar.veryShortWeekdaySymbols
        return Self.stripWindow(daily).compactMap { row in
            guard let d = trainingStripDate(row.date) else { return nil }
            let weekday = trainingStripCalendar.component(.weekday, from: d)
            return WeekStripDay(date: d, initial: symbols[weekday - 1], isToday: row.date == today, marked: status(row) == .good)
        }
    }

    /// `WeekStrip` selects by `Date`; the screen's contract is the ISO day key. A tap on a day the
    /// strip doesn't know (nil) is ignored rather than clearing the selection.
    private var selection: Binding<Date?> {
        Binding(get: { trainingStripDate(selectedDate) }, set: { if let d = $0 { onSelect(trainingStripISO(d)) } })
    }

    public var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                Text(daily.isEmpty ? "This week" : "This week · \(trainedCount)/\(windowed.count) trained")
                    .jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
                if daily.isEmpty {
                    Text("No training data yet.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                } else {
                    WeekStrip(days: days, tint: theme.color(.info), selected: selection)
                        .accessibilityIdentifier("training-day-strip")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)   // B-46 item 7: cards share one width
        }
        .jiHapticCue(.selection, on: selectedDate)   // W8-L1 (P-haptics) — oracle DayStrip.tsx:126 `if (!selected) hapticSelection()`: a re-tap of the selected day is no edge
    }
}
