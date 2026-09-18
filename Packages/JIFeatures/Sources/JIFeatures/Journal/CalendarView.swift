import SwiftUI
import JIDesign
import JIPersistence

/// Scope-aware calendar grid (oracle: `CalendarView.tsx`), fed by `JournalCalendar`. Highlights
/// days that have at least one entry.
public struct CalendarView: View {
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
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(JIColor.text)
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
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity, minHeight: 28)
                                    .background(
                                        Circle().fill(hasEntry ? JIColor.go.opacity(0.3) : Color.clear)
                                    )
                                    .foregroundStyle(JIColor.text)
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
