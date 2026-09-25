import SwiftUI
import JICore
import JIDesign

/// Day-nav strip (W3a-L2, mirrors `mobile/src/components/nutrition/NutritionWeekStrip.tsx`) —
/// selecting a chip re-queries that date's meal detail in place (`NutritionViewModel.selectDate`).
public struct NutritionWeekStrip: View {
    let days: [NutritionDailyRow]
    let selectedDate: String
    let onSelect: (String) -> Void

    @Environment(\.jiTheme) private var theme

    public init(days: [NutritionDailyRow], selectedDate: String, onSelect: @escaping (String) -> Void) {
        self.days = days; self.selectedDate = selectedDate; self.onSelect = onSelect
    }

    private var sorted: [NutritionDailyRow] { days.sorted { $0.date < $1.date } }

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
