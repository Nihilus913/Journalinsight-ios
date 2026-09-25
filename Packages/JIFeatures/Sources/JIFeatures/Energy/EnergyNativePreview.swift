import SwiftUI
import JICore
import JICompute
import JIDesign

/// §8.5 registry entry "Energy" — the cards `EnergyView.loaded` composes, over a fixture report
/// (a fixed "today", a fixture user target, one untracked day). Fixture values, not data — B-73:
/// the 1800 target stands in for a goal a user typed; JI ships none.
struct EnergyNativePreview: View {
    private let theme = JITheme.native
    private static let today = "2026-09-23"
    private static let goal = 1800.0

    private static let days: [EnergyDay] = (0..<7).map { i in
        let date = String(format: "2026-09-%02d", 17 + i)
        let intake: Double? = ([1690, 1560, 1720, nil, 1549, 1619, 467] as [Double?])[i]
        let tdee = 2300.0 + Double((i % 3) * 40)
        let deficit = intake.map { tdee - $0 }
        return EnergyDay(date: date, kcalConsumed: intake, tdeeRaw: tdee, tdeeCorrected: tdee,
                         deficitRaw: deficit, deficitCorrected: deficit,
                         deficitPctRaw: deficit.map { $0 / tdee * 100 }, deficitPctCorrected: deficit.map { $0 / tdee * 100 },
                         deficitClass: "mild", mealsLogged: intake == nil ? nil : 3)
    }

    private static let report = EnergyReport(
        days: days, avgDeficitRaw7d: 598, avgDeficitCorrected7d: 598, avgDeficitPct7d: 26,
        trackingDays: 6, compliant: true, tdeeEmpirical: 2340, goalIntakeKcal: nil
    )

    /// The band over the same fixture days (Health-shaped: a 1800 / rest split of the burn).
    private static let band: EnergyBandState = {
        let bandDays = days.map { EnergyBandDay(date: $0.date, basalKcal: 1800, activeKcal: ($0.tdeeRaw ?? 1800) - 1800, intakeKcal: $0.kcalConsumed) }
        let r = EnergyBand.compute(targetKcal: goal, days: bandDays, today: today)
        return EnergyBandState(result: r, burn: r.burn, reason: nil, targetKcal: goal)
    }()

    var body: some View {
        // B-57 W1 r5: the same sections `EnergyView.loaded` renders (hero, How we calculate this,
        // What you burn, How we calculate + the no-medical-judgement note, This week, Daily log).
        EnergySections(report: Self.report, days: Self.days, goal: Self.goal, today: Self.today, band: Self.band)
            .padding(.horizontal, 20).padding(.top, 8)
            .readableColumn()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(theme.color(.bg))
            .jiTheme(.native)
    }
}
