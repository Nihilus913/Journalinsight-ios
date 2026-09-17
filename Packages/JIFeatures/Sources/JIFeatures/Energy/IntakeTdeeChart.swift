import SwiftUI
import Charts
import JICore
import JIDesign

/// D2-E2 port — intake-vs-TDEE bars over the 28-day window, Swift Charts instead of the RN
/// oracle's hand-rolled `react-native-svg` geometry (`IntakeTdeeChart.tsx`; only `react-native-
/// svg` was available there, CONTEXT-D2-COMPOSITION.md §1 — Swift Charts is the native
/// equivalent). One bar pair per day (intake / TDEE — corrected when known, else raw); an
/// untracked day (`kcalConsumed == nil`) never draws a false zero (rule 5) — it's simply omitted
/// from the intake series for that date rather than drawn as a zero-height bar.
public struct IntakeTdeeChart: View {
    private let days: [EnergyDay]
    public init(days: [EnergyDay]) { self.days = days }

    public var body: some View {
        let sorted = days.sorted { $0.date < $1.date }
        if sorted.isEmpty {
            Text("No data yet").font(.caption).foregroundStyle(JIColor.muted)
        } else {
            Chart {
                ForEach(sorted, id: \.date) { day in
                    if let intake = day.kcalConsumed {
                        BarMark(x: .value("Date", day.date), y: .value("Intake", intake), width: .ratio(0.35))
                            .foregroundStyle(JIColor.info)
                            .position(by: .value("Series", "Intake"))
                    }
                    if let tdee = day.tdeeCorrected ?? day.tdeeRaw {
                        BarMark(x: .value("Date", day.date), y: .value("TDEE", tdee), width: .ratio(0.35))
                            .foregroundStyle(JIColor.mutedNested)
                            .position(by: .value("Series", "TDEE"))
                    }
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 132)
            legend
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendDot(color: JIColor.info, label: "Intake")
            legendDot(color: JIColor.mutedNested, label: "TDEE")
            legendDot(color: JIColor.muted, label: "Untracked")
        }.padding(.top, 6)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 10.5)).foregroundStyle(JIColor.muted)
        }
    }
}
