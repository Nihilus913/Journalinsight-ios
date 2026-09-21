import SwiftUI

public nonisolated struct WeekStripDay: Sendable, Equatable, Identifiable {
    public let date: Date, initial: String, isToday: Bool, marked: Bool
    public var id: Date { date }
    public init(date: Date, initial: String, isToday: Bool, marked: Bool) {
        self.date = date; self.initial = initial; self.isToday = isToday; self.marked = marked
    }
}

/// The seven days ending `today` (start-of-day in `calendar`). Callers pass the calendar —
/// JIDesign never reads `Calendar.current`.
public nonisolated func weekStripDays(ending today: Date, marked: Set<Date>, calendar: Calendar) -> [WeekStripDay] {
    let start = calendar.startOfDay(for: today)
    let symbols = calendar.veryShortWeekdaySymbols
    return (0..<7).reversed().compactMap { back in
        guard let d = calendar.date(byAdding: .day, value: -back, to: start) else { return nil }
        let weekday = calendar.component(.weekday, from: d)
        return WeekStripDay(date: d, initial: symbols[weekday - 1], isToday: back == 0, marked: marked.contains(d))
    }
}

/// §2b.4 Fitness calendar strip: circular day chips, weekday initial above, today filled with
/// the accent, a ring on days with activity, the selected day on the control fill.
public struct WeekStrip: View {
    let days: [WeekStripDay], tint: Color
    @Binding var selected: Date?
    @Environment(\.jiTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var chip: CGFloat = 36

    public init(days: [WeekStripDay], tint: Color, selected: Binding<Date?>) {
        self.days = days; self.tint = tint; self._selected = selected
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    Text(day.initial).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    Button { selected = day.date } label: {
                        Text(day.date, format: .dateTime.day())
                            .jiFont(.subheadline, weight: .semibold)
                            .frame(width: chip, height: chip)
                            .background(Circle().fill(day.isToday ? tint : (selected == day.date ? theme.color(.control) : .clear)))
                            .overlay(Circle().stroke(day.marked ? tint : .clear, lineWidth: 2))
                            .foregroundStyle(day.isToday ? Color.white : theme.color(.text))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(day.date, format: .dateTime.weekday(.wide).day()))
                    .accessibilityAddTraits(selected == day.date ? .isSelected : [])
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
