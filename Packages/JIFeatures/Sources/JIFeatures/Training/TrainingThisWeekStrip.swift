import SwiftUI
import JICore
import JIDesign

public nonisolated let trainingWeekLegend = "S strength · I intervals · R long run · + library workout"

/// The letter in a day circle: the plan kind, or "+" for an otherwise-rest day that holds a
/// library workout (W-B40 fixer, B40-V2 — the day sheet lists it, so the strip must too).
public nonisolated func trainingWeekDayGlyph(_ d: TrainingWeekDay) -> String {
    d.kind == .rest && !d.extras.isEmpty ? "+" : d.kind.rawValue
}

public nonisolated func trainingWeekDayAccessibilityLabel(_ d: TrainingWeekDay) -> String {
    var parts = [planWeekdayNames[d.weekday]]
    if d.isToday { parts.append("today") }
    parts.append(d.kind.word)
    if d.kind == .strength, let name = d.sessionName { parts.append(name) }
    if d.done == true { parts.append("done") } else if d.done == false { parts.append("missed") }
    if !d.extras.isEmpty { parts.append("plus " + d.extras.joined(separator: ", ")) }
    return parts.joined(separator: ", ")
}

/// B-57 W5 board 3/01: seven day circles (S / I / R / –), "n of N done", legend, "Edit week".
/// A tap selects that day for the "This day" card below, as the old day strip did.
/// Colours (rule 6): the only green is the done fill (a status); today = bold day initial,
/// the selected day = the accent (`info`) ring; the letters themselves stay text/muted.
public struct TrainingThisWeekStrip: View {
    /// W-FIX3 BUG-33 (same rule as `TrainingDayStrip`): seven fixed circles cannot hold AX
    /// letters side by side, so the row stops scaling at xxxLarge; header and legend keep full DT.
    nonisolated static let maxTypeSize: DynamicTypeSize = .xxxLarge

    let summary: TrainingWeekSummary
    let selectedDate: String
    let onSelect: (String) -> Void
    let onEditWeek: () -> Void
    @Environment(\.jiTheme) private var theme

    public init(summary: TrainingWeekSummary, selectedDate: String, onSelect: @escaping (String) -> Void, onEditWeek: @escaping () -> Void) {
        self.summary = summary; self.selectedDate = selectedDate; self.onSelect = onSelect; self.onEditWeek = onEditWeek
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: JISpacing.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week").jiFont(.cardTitle, weight: .bold).foregroundStyle(theme.color(.text))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(summary.doneText).jiFont(.subheadline)
                    .foregroundStyle(theme.color(summary.planDone == nil ? .muted : .text))
                    .accessibilityIdentifier("training-week-done")
            }
            HStack(spacing: 0) {
                ForEach(summary.days) { day in
                    Button { onSelect(day.date) } label: { dayCell(day) }
                        .buttonStyle(.pressableScale)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityLabel(trainingWeekDayAccessibilityLabel(day))
                        .accessibilityAddTraits(day.date == selectedDate ? .isSelected : [])
                        .accessibilityIdentifier("training-week-day-\(day.weekday)")
                }
            }
            .dynamicTypeSize(...Self.maxTypeSize)
            Text(trainingWeekLegend).jiFont(.micro).foregroundStyle(theme.color(.muted))
                .accessibilityIdentifier("training-week-legend")
            // W-B57-W5 fixer (B2): a full-width JI secondary button under the legend, never a
            // tinted text link (W-GUI DEV-07).
            Button("Edit week", action: onEditWeek)
                .buttonStyle(.jiSecondary)
                .accessibilityIdentifier("training-edit-week")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jiHapticCue(.selection, on: selectedDate)
    }

    private func dayCell(_ d: TrainingWeekDay) -> some View {
        let selected = d.date == selectedDate
        return VStack(spacing: 6) {
            let workoutOnly = d.kind == .rest && !d.extras.isEmpty
            ZStack {
                if d.kind == .rest && !workoutOnly {
                    Circle().strokeBorder(theme.color(.muted), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                } else {
                    Circle().fill(d.done == true ? theme.color(.go).opacity(0.3) : theme.color(.nested))
                }
                if selected { Circle().strokeBorder(theme.color(.info), lineWidth: 2) }
                Text(trainingWeekDayGlyph(d)).jiFont(.subheadline, weight: .bold)
                    .foregroundStyle(theme.color(d.kind == .rest && !workoutOnly ? .muted : .text))
            }
            .frame(width: 34, height: 34)
            // A plan day that ALSO holds a library workout: a small "+" badge.
            .overlay(alignment: .topTrailing) {
                if !d.extras.isEmpty && !workoutOnly {
                    Text("+").jiFont(.micro, weight: .bold).foregroundStyle(theme.color(.text))
                        .offset(x: 4, y: -4)
                        .accessibilityHidden(true)
                }
            }
            Text(String(trainingWeekdayShortNames[d.weekday].prefix(1)))
                .jiFont(.caption, weight: d.isToday ? .bold : .regular)
                .foregroundStyle(theme.color(d.isToday ? .text : .muted))
        }
    }
}
