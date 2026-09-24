import SwiftUI
import JICore
import JIDesign

/// §8.5 registry entry "Energy" — the cards `EnergyView.loaded` composes, over a fixture report.
struct EnergyNativePreview: View {
    @State private var range: TrendRange = .month
    private let theme = JITheme.native

    private static let days: [EnergyDay] = (0..<28).map { i in
        let day = 28 - i
        let date = String(format: "2026-08-%02d", max(1, day))
        let intake = [2180.0, 2310, 2050, 2620, 2400, 1980, 2290][i % 7]
        let tdee = 2760.0 + Double((i % 5) * 40)
        let deficit = tdee - intake
        return EnergyDay(date: date, kcalConsumed: i % 9 == 0 ? nil : intake,
                         tdeeRaw: tdee, tdeeCorrected: tdee,
                         deficitRaw: deficit, deficitCorrected: deficit,
                         deficitPctRaw: deficit / tdee * 100, deficitPctCorrected: deficit / tdee * 100,
                         deficitClass: deficit > 700 ? "aggressive" : "mild",
                         mealsLogged: i % 9 == 0 ? nil : 3)
    }

    private static let report = EnergyReport(
        days: days, avgDeficitRaw7d: 466, avgDeficitCorrected7d: 466, avgDeficitPct7d: 17,
        trackingDays: 6, compliant: true, tdeeEmpirical: 2760, goalIntakeKcal: 2400
    )

    private func balancePoints() -> [TrendPoint] {
        Self.days.sorted { $0.date < $1.date }.suffix(range.days).compactMap { day in
            guard let deficit = day.deficitCorrected, let date = trainingStripDate(day.date) else { return nil }
            return TrendPoint(date: date, value: -deficit)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            JISectionHeader("Balance")
            AdaptiveHStack {
                EnergyHero(report: Self.report)
                Surface(padding: 18) {
                    TrendChart(points: balancePoints(), tint: theme.color(.info), unit: "kcal", range: $range, showAll: nil)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("What you burn").jiFont(.cardTitle).foregroundStyle(theme.color(.text)).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("7-day average").jiFont(.footnote).foregroundStyle(theme.color(.muted))
            }
            Surface(level: 1) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("—").jiNumeral(.numeralMedium, tint: .muted)
                        Label(JIMissingReason.notInHealthYet.rawValue, systemImage: "minus").jiFont(.subheadline, weight: .semibold)
                            .foregroundStyle(theme.color(.muted))
                    }
                    Text(energyBurnCardCopy).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("energy.whatYouBurn")
            }
            HowWeCalculate(title: JIExplainers.energyBalanceTitle, steps: JIExplainers.energyBalanceSteps, note: JIExplainers.energyBalanceNote)
                .accessibilityIdentifier("energy.howWeCalculate")
            JISectionHeader("Intake vs TDEE")
            Surface(padding: 18) { IntakeTdeeChart(days: Self.days) }
            JISectionHeader("Daily log")
            Surface(padding: 18) { DeficitDayList(days: Array(Self.days.prefix(5))) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 8)
        .readableColumn()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.color(.bg))
    }
}
