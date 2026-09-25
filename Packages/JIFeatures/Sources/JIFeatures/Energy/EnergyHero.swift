import SwiftUI
import JICore
import JICompute
import JIDesign

/// Sign-convention helpers shared by `EnergyHero`, `IntakeTdeeChart`, and `DeficitDayList` — ports
/// `mobile/src/components/energy/deficitFormat.ts` verbatim. The compute/hub convention is
/// `deficit = TDEE - intake` (positive = deficit, negative = surplus); the UI shows the *balance*
/// (`-deficit`) the way people read it ("-466" for a deficit, "+559" for a surplus).
@MainActor
public enum EnergyFormat {
    public static func balanceText(_ deficit: Double?) -> String {
        guard let deficit, !deficit.isNaN else { return "—" }
        let balance = -deficit
        let rounded = balance.rounded()
        if rounded == 0 { return "0" }
        let r = String(Int(abs(rounded)))
        return balance > 0 ? "+\(r)" : "-\(r)"
    }

    /// Surplus and untracked are both neutral (`muted`); `dangerous` is the one fail-type band and
    /// may use `danger` (rule 6: green stays reserved for verdict/score/status, never used here).
    /// B-33: the roles are unchanged; only their resolution moved to the active theme, so the
    /// caller passes the one its screen installed.
    public static func deficitColor(_ deficit: Double?, class deficitClass: String?, theme: JITheme) -> Color {
        guard let deficit else { return theme.color(.muted) }
        if deficit < 0 || deficitClass == "surplus" { return theme.color(.muted) }
        switch deficitClass {
        case "dangerous": return theme.color(.danger)
        case "aggressive": return theme.color(.reduced)
        default: return theme.color(.info)
        }
    }
}

// MARK: - B-57 W1 r5: the board's hero ("7-DAY BALANCE · −598 kcal a day")

/// The hero numeral: the signed 7-day balance (`-deficit`) with a typographic minus, no unit.
public nonisolated func energyHeroNumeral(_ deficit: Double?) -> String {
    guard let deficit, deficit.isFinite else { return "—" }
    let balance = -deficit.rounded()
    if balance == 0 { return "0" }
    let r = String(Int(abs(balance)))
    return balance > 0 ? "+\(r)" : "\u{2212}\(r)"
}

/// The line under the numeral. Only the sign of the balance — the plan band ("Deep deficit",
/// "On plan", …) comes from the goal band, which is left for W2.
public nonisolated struct EnergyHeroDirection: Sendable, Equatable {
    public let word: String
    public let symbolName: String
}

public nonisolated func energyHeroDirection(_ deficit: Double?) -> EnergyHeroDirection? {
    guard let deficit, deficit.isFinite else { return nil }
    let r = deficit.rounded()
    if r > 0 { return EnergyHeroDirection(word: "Deficit", symbolName: "arrow.down") }
    if r < 0 { return EnergyHeroDirection(word: "Surplus", symbolName: "arrow.up") }
    return EnergyHeroDirection(word: "Even", symbolName: "equal")
}

/// The board's explanation line, from real figures only (the sign, the tracked days, the goal).
public nonisolated func energyHeroExplanation(avgDeficit: Double?, trackingDays: Int, goal: Double?) -> String {
    guard let avgDeficit, avgDeficit.isFinite else { return "— \(JIMissingReason.noData.rawValue) for the last 7 days yet." }
    let r = avgDeficit.rounded()
    let lead = r > 0 ? "You are eating less than you burn" : (r < 0 ? "You are eating more than you burn" : "What you eat matches what you burn")
    let goalText = goal.flatMap { $0.isFinite && $0 > 0 ? "Your goal is \(Int($0.rounded())) kcal a day." : nil } ?? "No goal set."
    return "\(lead), averaged over \(trackingDays) of the last 7 days. \(goalText)"
}

/// Board hero (`2 Monitor/06 Energy.png`): "7-DAY BALANCE", the 7-day average balance large in
/// the calorie tint with "kcal a day", the direction line and the explanation. Below
/// `MIN_TRACKING_DAYS` (4) the numeral is "—" with the "more days needed" reason instead.
/// The old Raw / Adj / Deficit % chips and the sustainable-zone bar are gone (not on the board);
/// B-57 W2 (B-73): once the phone's band has a 7-day Health balance, the hero shows THAT balance,
/// its plan-band class ("On plan", …), the band sentence and the implied deficit (information
/// only). Until then it keeps the hub report's balance. `goal` is the user's own target only —
/// the hub report's seeded `goalIntakeKcal` is never shown.
public struct EnergyHero: View {
    private let report: EnergyReport
    private let goal: Double?
    private let band: EnergyBandState
    private let minTrackingDays: Int
    @Environment(\.jiTheme) private var theme

    public init(report: EnergyReport, goal: Double? = nil, band: EnergyBandState = .none, minTrackingDays: Int = 4) {
        self.report = report; self.goal = goal; self.band = band; self.minTrackingDays = minTrackingDays
    }

    /// The band's balance (eaten − burned), as a hub-convention deficit (burned − eaten).
    private var bandDeficit: Double? { band.result?.balanceKcal.map { Double(-$0) } }
    private var usesBand: Bool { bandDeficit != nil }
    private var gated: Bool { !usesBand && report.trackingDays < minTrackingDays }
    private var deficit: Double? { usesBand ? bandDeficit : (gated ? nil : report.avgDeficitCorrected7d) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("7-DAY BALANCE").jiFont(.caption, weight: .bold).foregroundStyle(theme.color(nutritionKcalTintRole))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) { numeral; unit }
                VStack(alignment: .leading, spacing: 2) { numeral; unit }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("7-day energy balance")
            .accessibilityValue(deficit == nil ? JIMissingReason.noData.rawValue : "\(EnergyFormat.balanceText(deficit)) kcal a day")
            .accessibilityIdentifier("energy.hero.balance")
            if gated {
                let n = minTrackingDays - report.trackingDays
                Text("— \(n) more day\(n == 1 ? "" : "s") needed for reliable averages")
                    .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("energy.hero.minDataGate")
            } else if usesBand, let result = band.result {
                Label(EnergyBandCopy.heroReason(result: result, reason: band.reason), systemImage: energyHeroDirection(deficit)?.symbolName ?? "equal")
                    .jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(nutritionKcalTintRole))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("energy-hero-class")
                if let sentence = EnergyBandCopy.sentence(result) {
                    Text(sentence).jiFont(.subheadline).foregroundStyle(theme.color(.text))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("energy.hero.explanation")
                }
                if let implied = EnergyBandCopy.impliedDeficit(result) {
                    // Information only: plain muted text, never a verdict colour.
                    Text(implied).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("energy-implied-deficit")
                }
            } else {
                if let dir = energyHeroDirection(deficit) {
                    Label(dir.word, systemImage: dir.symbolName)
                        .jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(nutritionKcalTintRole))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("energy.hero.direction")
                }
                Text(energyHeroExplanation(avgDeficit: deficit, trackingDays: report.trackingDays, goal: goal))
                    .jiFont(.subheadline).foregroundStyle(theme.color(.text))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("energy.hero.explanation")
            }
            if let warning = report.complianceWarning {
                Text("⚠ \(warning)").jiFont(.footnote).foregroundStyle(theme.color(.reduced))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Warning: \(warning)")
                    .accessibilityIdentifier("energy.hero.complianceWarning")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var numeral: some View {
        Text(energyHeroNumeral(deficit))
            .jiNumeral(.numeralDisplay, weight: .heavy)
            .foregroundStyle(theme.color(deficit == nil ? .muted : nutritionKcalTintRole))
            .contentTransition(.numericText())
            .lineLimit(1).minimumScaleFactor(0.7)
    }

    private var unit: some View {
        Text("kcal a day").jiFont(.body).foregroundStyle(theme.color(.muted))
    }
}
