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
    public init(days: [EnergyDay]) { self.days = days }

    public var body: some View {
        let sorted = days.sorted { $0.date > $1.date }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sorted, id: \.date) { day in
                row(day)
                if day.date != sorted.last?.date {
                    Divider().overlay(JIColor.nested)
                }
            }
        }
    }

    private func row(_ day: EnergyDay) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Circle().fill(dotColor(day)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(day.date).font(.footnote.bold()).foregroundStyle(JIColor.text)
                Text("intake \(fmt(day.kcalConsumed)) · TDEE \(fmt(day.tdeeCorrected)) · \(day.deficitClass ?? "—")")
                    .font(.caption2).foregroundStyle(JIColor.muted)
            }
            Spacer()
            Text(EnergyFormat.balanceText(day.deficitCorrected))
                .font(.subheadline.bold())
                .foregroundStyle(EnergyFormat.deficitColor(day.deficitCorrected, class: day.deficitClass))
        }
        .padding(.vertical, 10)
    }

    private func dotColor(_ day: EnergyDay) -> Color {
        guard let meals = day.mealsLogged, day.kcalConsumed != nil else { return JIColor.danger }
        return meals >= 2 ? JIColor.info : JIColor.reduced
    }

    private func fmt(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(Int(v.rounded()))
    }
}
