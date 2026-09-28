import SwiftUI
import JICore
import JIDesign

/// Day-nav strip (W3a-L2, mirrors `mobile/src/components/nutrition/NutritionWeekStrip.tsx`) —
/// selecting a chip re-queries that date's meal detail in place (`NutritionViewModel.selectDate`).
public struct NutritionWeekStrip: View {
    let days: [NutritionDailyRow]
    let selectedDate: String
    /// W-FIX8 M-2: the device's today. Set → the strip is always the seven days ending today (an
    /// unlogged day is a plain chip, not a missing one); nil → the payload's days, as before.
    let today: String?
    let onSelect: (String) -> Void

    @Environment(\.jiTheme) private var theme

    public init(days: [NutritionDailyRow], selectedDate: String, today: String? = nil, onSelect: @escaping (String) -> Void) {
        self.days = days; self.selectedDate = selectedDate; self.today = today; self.onSelect = onSelect
    }

    private var sorted: [NutritionDailyRow] {
        today.map { nutritionStripRows(week: days, today: $0) } ?? days.sorted { $0.date < $1.date }
    }

    /// §2b.4: the Fitness calendar strip. A day with logged calories is "marked" (the accent
    /// ring); an unlogged day stays plain — never a zero standing in for "not tracked" (rule 5).
    private var stripDays: [WeekStripDay] {
        let symbols = trainingStripCalendar.veryShortWeekdaySymbols
        return sorted.compactMap { day in
            guard let d = trainingStripDate(day.date) else { return nil }
            let weekday = trainingStripCalendar.component(.weekday, from: d)
            return WeekStripDay(date: d, initial: symbols[weekday - 1],
                                isToday: day.date == selectedDate, marked: day.kcalConsumed != nil)
        }
    }

    private var selection: Binding<Date?> {
        Binding(get: { trainingStripDate(selectedDate) }, set: { if let d = $0 { onSelect(trainingStripISO(d)) } })
    }

    public var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                WeekStrip(days: stripDays, tint: theme.color(.info), selected: selection)
                    // W-FIX3 BUG-33: seven rings cannot grow past a seventh of the card; at AX
                    // sizes they overlapped. The strip caps its type size (each chip keeps its
                    // full VoiceOver label) and the caption below carries the large text.
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .accessibilityIdentifier("nutrition-week-strip")
                if let day = sorted.first(where: { $0.date == selectedDate }) {
                    Text(verbatim: nutritionWeekCaption(date: day.date, kcal: day.kcalConsumed))
                        .jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("nutrition-week-day-\(day.date)")
                }
                // W-FIX8 M-2: the chips' two marks, said once (W-GUI: logged = ring, selected = fill).
                Text(nutritionStripLegend).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nutrition-week-legend")
            }
        }
    }

    /// Not `nonisolated` (this type stays `@MainActor` under JIFeatures' default isolation) but
    /// pure — a plain function so it stays independently testable, mirroring `StatChip`'s label
    /// builders (JIDesign).
    static func weekdayLabel(_ isoDate: String) -> String {
        guard let date = NutritionWeekStrip.dayFormatter.date(from: isoDate) else { return isoDate }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// W-FIX8 M-2: the week strip's legend.
public nonisolated let nutritionStripLegend = "Ring = food logged · filled = selected day"

/// W-FIX8 M-2: the seven local days ending `today`, oldest first — each the week's row for that
/// day, or an empty row (no kcal → no ring, never a zero) when nothing was logged.
public nonisolated func nutritionStripRows(week: [NutritionDailyRow], today: String) -> [NutritionDailyRow] {
    guard let end = trainingStripDate(today) else { return week.sorted { $0.date < $1.date } }
    return (0..<7).reversed().compactMap { back in
        trainingStripCalendar.date(byAdding: .day, value: -back, to: end).map { d in
            let iso = trainingStripISO(d)
            return week.first { $0.date == iso } ?? NutritionDailyRow(date: iso)
        }
    }
}
