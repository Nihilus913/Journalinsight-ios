import SwiftUI
import JICore
import JIDesign

/// §8.5 registry entry "Energy" — the cards `EnergyView.loaded` composes, over a fixture report
/// (a fixed "today", a fixture goal, one untracked day).
struct EnergyNativePreview: View {
    private let theme = JITheme.native
    private static let today = "2026-09-23"
    private static let goal = 1700.0

    private static let days: [EnergyDay] = (0..<7).map { i in
        let date = String(format: "2026-09-%02d", 17 + i)
        let intake: Double? = ([1690, 1560, 1720, nil, 1480, 1905, 467] as [Double?])[i]
        let tdee = 2300.0 + Double((i % 3) * 40)
        let deficit = intake.map { tdee - $0 }
        return EnergyDay(date: date, kcalConsumed: intake, tdeeRaw: tdee, tdeeCorrected: tdee,
                         deficitRaw: deficit, deficitCorrected: deficit,
                         deficitPctRaw: deficit.map { $0 / tdee * 100 }, deficitPctCorrected: deficit.map { $0 / tdee * 100 },
                         deficitClass: "mild", mealsLogged: intake == nil ? nil : 3)
    }

    private static let report = EnergyReport(
        days: days, avgDeficitRaw7d: 598, avgDeficitCorrected7d: 598, avgDeficitPct7d: 26,
        trackingDays: 6, compliant: true, tdeeEmpirical: 2340, goalIntakeKcal: goal
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EnergyHero(report: Self.report)
            EnergyBurnCard()
            EnergyThisWeek(days: Self.days, goal: Self.goal, today: Self.today)
            JISectionHeader("Daily log")
            Surface(padding: 18) { DeficitDayList(days: Self.days, goal: Self.goal, today: Self.today) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 8)
        .readableColumn()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.color(.bg))
    }
}
