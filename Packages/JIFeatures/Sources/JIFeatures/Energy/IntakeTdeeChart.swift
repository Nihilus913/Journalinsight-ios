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
    /// §8.4: chart geometry scales with the type size instead of clipping the bars' labels.
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 132
    private let days: [EnergyDay]
    @Environment(\.jiTheme) private var theme
    public init(days: [EnergyDay]) { self.days = days }

    public var body: some View {
        let sorted = days.sorted { $0.date < $1.date }
        if sorted.isEmpty {
            Text("No data yet").jiFont(.caption).foregroundStyle(theme.color(.muted))
                .accessibilityLabel("No data yet")
        } else {
            Chart {
                ForEach(sorted, id: \.date) { day in
                    if let intake = day.kcalConsumed {
                        BarMark(x: .value("Date", day.date), y: .value("Intake", intake), width: .ratio(0.35))
                            .foregroundStyle(theme.color(.info))
                            .position(by: .value("Series", "Intake"))
                    }
                    if let tdee = day.tdeeCorrected ?? day.tdeeRaw {
                        BarMark(x: .value("Date", day.date), y: .value("TDEE", tdee), width: .ratio(0.35))
                            .foregroundStyle(theme.color(.mutedNested))
                            .position(by: .value("Series", "TDEE"))
                    }
                }
            }
            .chartXAxis(.hidden)
            .frame(height: chartHeight)
            .accessibilityLabel("Intake versus TDEE, daily")
            .accessibilityIdentifier("energy.chart.intakeTdee")
            legend
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendDot(color: theme.color(.info), label: "Intake")
            legendDot(color: theme.color(.mutedNested), label: "TDEE")
            legendDot(color: theme.color(.muted), label: "Untracked")
        }.padding(.top, 6)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).jiFont(.micro).foregroundStyle(theme.color(.muted))
        }
        .accessibilityLabel(label)
    }
}
