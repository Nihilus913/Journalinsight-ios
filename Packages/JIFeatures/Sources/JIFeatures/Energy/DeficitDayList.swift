import SwiftUI
import JICore
import JIDesign

/// D2-E3 port — the daily log (`DeficitDayList.tsx`). Newest-first, one row per day: a status dot
/// (tracked/partial/untracked, mirrored from `trackedStatus` in the RN oracle's `DayStrip.tsx`),
/// date, intake/TDEE/class line, and the balance colored by `EnergyFormat.deficitColor`. The RN
/// row taps through to Nutrition on that date — no cross-tab navigation exists yet in this wave
/// (Nutrition ships in sibling lane L2), so this list is display-only; a future wave wires the tap.
public struct DeficitDayList: View {
    private let days: [EnergyDay]
    @Environment(\.jiTheme) private var theme
    public init(days: [EnergyDay]) { self.days = days }

    public var body: some View {
        let sorted = days.sorted { $0.date > $1.date }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sorted, id: \.date) { day in
                row(day)
                if day.date != sorted.last?.date {
                    Divider().overlay(theme.color(.hairlineNested))
                }
            }
        }
    }

    /// §2b.2: one 44-pt inset-grouped row per day, the status dot carried as the row's tint.
    private func row(_ day: EnergyDay) -> some View {
        JIRow(title: day.date,
              subtitle: "intake \(fmt(day.kcalConsumed)) · TDEE \(fmt(day.tdeeCorrected)) · \(day.deficitClass ?? "—")",
              systemImage: "circle.fill", tint: dotColor(day)) {
            Text(EnergyFormat.balanceText(day.deficitCorrected))
                .jiFont(.subheadline, weight: .bold)
                .foregroundStyle(EnergyFormat.deficitColor(day.deficitCorrected, class: day.deficitClass, theme: theme))
        }
        // Display-only rows (RN's `View ${d.date} in Nutrition` tap-through has no Swift
        // counterpart yet), so the label is the row's visible text.
        .accessibilityLabel("\(day.date), intake \(fmt(day.kcalConsumed)), TDEE \(fmt(day.tdeeCorrected)), \(day.deficitClass ?? "unknown")")
        .accessibilityValue("\(EnergyFormat.balanceText(day.deficitCorrected)) kcal")
        .accessibilityIdentifier("energy.day.\(day.date)")
        .padding(.vertical, 2)
    }

    private func dotColor(_ day: EnergyDay) -> Color {
        guard let meals = day.mealsLogged, day.kcalConsumed != nil else { return theme.color(.danger) }
        return meals >= 2 ? theme.color(.info) : theme.color(.reduced)
    }

    private func fmt(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(Int(v.rounded()))
    }
}
