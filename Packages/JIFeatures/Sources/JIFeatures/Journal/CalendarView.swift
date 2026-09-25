import SwiftUI
import JIDesign
import JIPersistence

/// Scope-aware calendar grid (oracle: `CalendarView.tsx`), fed by `JournalCalendar`. Highlights
/// days that have at least one entry.
public struct CalendarView: View {
    @Environment(\.jiTheme) private var theme
    let scope: JournalCalendar.Scope
    let anchor: Date
    let entryDates: Set<String>
    let onSelectDay: (String) -> Void
    let onShift: (Int) -> Void

    public init(
        scope: JournalCalendar.Scope, anchor: Date, entryDates: Set<String>,
        onSelectDay: @escaping (String) -> Void, onShift: @escaping (Int) -> Void
    ) {
        self.scope = scope; self.anchor = anchor; self.entryDates = entryDates
        self.onSelectDay = onSelectDay; self.onShift = onShift
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    public var body: some View {
        Surface {
            VStack(spacing: 10) {
                HStack {
                    Button { onShift(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.pressableScale)
                        .accessibilityLabel("Previous \(JournalCalendar.scopeLabel(scope))")
                    Spacer()
                    Text(JournalCalendar.rangeLabel(scope, anchor: anchor))
                        .jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.text))
                    Spacer()
                    Button { onShift(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.pressableScale)
                        .accessibilityLabel("Next \(JournalCalendar.scopeLabel(scope))")
                }
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(JournalCalendar.scopeDays(scope, anchor: anchor).enumerated()), id: \.offset) { _, day in
                        if let day {
                            let hasEntry = entryDates.contains(day)
                            Button { onSelectDay(day) } label: {
                                Text(day.suffix(2))
                                    .jiFont(.label)
                                    .frame(maxWidth: .infinity, minHeight: 28)
                                    .background(
                                        Circle().fill(hasEntry ? theme.color(.go).opacity(0.3) : Color.clear)
                                    )
                                    .foregroundStyle(theme.color(.text))
                            }
                            .buttonStyle(.plain)
                            // Oracle `CalendarView.tsx` labels a day cell with its date + entry
                            // count; only presence is known here, so the count becomes a value.
                            .accessibilityLabel(day)
                            .accessibilityValue(hasEntry ? "Has entries" : "No entries")
                        } else {
                            Color.clear.frame(minHeight: 28)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - B-57 W1 JournalCalendar board (fixer f3)

/// Board 4/02 — the Journal calendar as its own screen: the period's name as the title, back plus
/// previous / next, a Week · Month · Year control, the grid (a dot under a written day, today
/// filled), the Entries and Average-mood cards, and the chosen day's card.
public struct JournalCalendarScreen: View {
    @Bindable var model: JournalViewModel
    @State private var tab: JournalCalendarTab = .month
    @State private var anchor: Date
    @State private var selectedDay: String
    @Environment(\.jiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(model: JournalViewModel) {
        self.model = model
        _anchor = State(initialValue: model.today)
        _selectedDay = State(initialValue: JournalCalendarZurich.isoDay(model.today))
    }

    private var todayISO: String { JournalCalendarZurich.isoDay(model.today) }
    private var stats: JournalPeriodStats {
        journalPeriodStats(entries: model.entries, tab: tab, anchor: anchor, today: model.today)
    }

    public var body: some View {
        List {
            Section {
                Picker("Range", selection: $tab) {
                    ForEach(JournalCalendarTab.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("journal-calendar-tab")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section { grid.listRowBackground(Color.clear) }

            Section {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) { entriesCard; moodCard }
                    VStack(spacing: 12) { entriesCard; moodCard }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section { dayCard }
        }
        .jiNativeFormChrome()
        .jiTheme(.native)
        .navigationTitle(journalCalendarTitle(tab, anchor: anchor))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { anchor = journalShiftAnchor(tab, anchor: anchor, dir: -1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous \(tab.title.lowercased())")
                Button { anchor = journalShiftAnchor(tab, anchor: anchor, dir: 1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next \(tab.title.lowercased())")
            }
        }
    }

    // MARK: Grid

    @ViewBuilder private var grid: some View {
        switch tab {
        case .week: dayGrid(JournalCalendar.scopeDays(.week, anchor: anchor))
        case .month: dayGrid(JournalCalendar.monthGrid(month: anchor).trimmedTrailingWeeks())
        case .year: yearGrid
        }
    }

    private func dayGrid(_ days: [String?]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                Text(d).jiFont(.label, tint: .muted).accessibilityHidden(true)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day { dayCell(day) } else { Color.clear.frame(minHeight: 44) }
            }
        }
    }

    private func dayCell(_ day: String) -> some View {
        let written = model.entryDates.contains(day)
        let isToday = day == todayISO
        let isFuture = day > todayISO
        let selected = day == selectedDay && !isToday
        return Button { selectedDay = day } label: {
            VStack(spacing: 3) {
                Text(String(Int(day.suffix(2)) ?? 0))
                    .jiFont(.subheadline, weight: .semibold, tint: isToday ? .bg : (isFuture ? .muted : .text))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(minWidth: 36, minHeight: 36)
                    .background {
                        if isToday { Circle().fill(theme.color(.info)) }
                        else if selected { Circle().strokeBorder(theme.color(.info), lineWidth: 1.5) }
                    }
                Circle().fill(written && !isToday ? theme.color(.info) : Color.clear).frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day)
        .accessibilityValue(written ? "Written" : isFuture ? "Still to come" : "Not written")
        .accessibilityAddTraits(day == selectedDay ? .isSelected : [])
    }

    private var yearGrid: some View {
        let year = JournalCalendarZurich.calendar.component(.year, from: anchor)
        let counts = journalYearMonthCounts(dates: Array(model.entryDates), year: year)
        let names = JournalCalendarZurich.formatter("MMM").shortStandaloneMonthSymbols ?? []
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 3)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<12, id: \.self) { i in
                VStack(spacing: 4) {
                    Text(i < names.count ? names[i] : "\(i + 1)").jiFont(.footnote, tint: .muted)
                    Text(counts[i] > 0 ? "\(counts[i])" : "—")
                        .jiFont(.statValue, weight: .semibold, tint: counts[i] > 0 ? .info : .muted)
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.color(.surface2)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(i < names.count ? names[i] : "Month \(i + 1)")
                .accessibilityValue(counts[i] == 0 ? "No entries" : "\(counts[i]) days written")
            }
        }
    }

    // MARK: Cards

    private var entriesCard: some View {
        let s = stats
        let word: BoardStatus = s.entryDays == 0
            ? BoardStatus(word: "None yet", systemImage: "minus", role: .muted)
            : BoardStatus(word: "\(Int((100 * Double(s.entryDays) / Double(max(s.elapsedDays, 1))).rounded()))% of days",
                          systemImage: "checkmark", role: .info)
        return boardCard {
            BoardSummaryCard(systemImage: "book.closed", title: "Entries", value: "\(s.entryDays)",
                             unit: "of \(s.elapsedDays) days", status: word)
        }
    }

    private var moodCard: some View {
        let s = stats
        return boardCard {
            BoardSummaryCard(systemImage: "face.smiling", title: "Average mood",
                             value: s.averageMood == nil ? nil : journalAverageMoodText(s.averageMood), unit: "/ 5",
                             status: BoardStatus(word: s.averageMood == nil ? "No data" : s.trendWord,
                                                 systemImage: "minus", role: .muted))
        }
    }

    private func boardCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 22).fill(theme.color(.surface)))
    }

    @ViewBuilder private var dayCard: some View {
        let written = model.entryDates.contains(selectedDay)
        let date = JournalCalendarZurich.date(fromISODay: selectedDay)
        let label = date.map { JournalCalendarZurich.formatter("EEE d MMM").string(from: $0) } ?? selectedDay
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).jiFont(.subheadline, weight: .semibold, tint: .text)
                Spacer(minLength: 8)
                BoardStatusLabel(word: written ? "Written" : "Not written", systemImage: written ? "checkmark" : "minus",
                                 role: written ? .info : .reduced)
            }
            if written, let entry = model.entries.first(where: { $0.date == selectedDay }) {
                Button("Open entry") { model.beginEditEntry(entry) }
                    .buttonStyle(.plain).jiFont(.subheadline, weight: .semibold, tint: .info)
            } else if selectedDay <= todayISO {
                Button(selectedDay == todayISO ? "Write today\u{2019}s entry" : "Write an entry") {
                    model.beginNewEntry(onDay: selectedDay)
                }
                .buttonStyle(.plain).jiFont(.subheadline, weight: .semibold, tint: .info)
                .accessibilityIdentifier("journal-calendar-write")
            }
        }
        .padding(.vertical, 4)
    }
}

private extension Array where Element == String? {
    /// The 42-cell month grid without its all-empty trailing weeks.
    func trimmedTrailingWeeks() -> [String?] {
        var cells = self
        while cells.count >= 7, cells.suffix(7).allSatisfy({ $0 == nil }) { cells.removeLast(7) }
        return cells
    }
}
