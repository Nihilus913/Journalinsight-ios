import SwiftUI
import JICore
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
    public static func deficitColor(_ deficit: Double?, class deficitClass: String?) -> Color {
        guard let deficit else { return JIColor.muted }
        if deficit < 0 || deficitClass == "surplus" { return JIColor.muted }
        switch deficitClass {
        case "dangerous": return JIColor.danger
        case "aggressive": return JIColor.reduced
        default: return JIColor.info
        }
    }
}

/// D2-E1 port — one prominent adjusted-deficit numeral, a filled bar against the sustainable-
/// deficit zone (0...28%, `DEFICIT_AGGRESSIVE_MAX_PCT`), and raw/adjusted/percent chips beneath.
/// Below `MIN_TRACKING_DAYS` (4 — `EnergyView`'s min-data gate) the caller shows a "more days
/// needed" wall instead of this numeral; `trackingDays` and `complianceWarning` are always shown.
public struct EnergyHero: View {
    private let report: EnergyReport
    private let minTrackingDays: Int

    public init(report: EnergyReport, minTrackingDays: Int = 4) {
        self.report = report; self.minTrackingDays = minTrackingDays
    }

    private static let sustainableMaxPct = 22.0
    private static let aggressiveMaxPct = 28.0

    public var body: some View {
        Surface(level: 1, radius: JIRadius.hero, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("ENERGY BALANCE · LAST 7 DAYS").font(.caption.bold()).foregroundStyle(JIColor.muted)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("\(report.trackingDays)/7 tracked").font(.caption2.bold()).foregroundStyle(JIColor.muted)
                        .accessibilityLabel("\(report.trackingDays) of 7 days tracked")
                }
                if report.trackingDays < minTrackingDays {
                    Text("\(minTrackingDays - report.trackingDays) more day\(minTrackingDays - report.trackingDays == 1 ? "" : "s") needed for reliable averages")
                        .font(.footnote).foregroundStyle(JIColor.muted)
                        .accessibilityIdentifier("energy.hero.minDataGate")
                } else {
                    numeralAndBar
                    HStack(spacing: 8) {
                        chip(label: "Raw", value: "\(EnergyFormat.balanceText(report.avgDeficitRaw7d)) kcal/d")
                        chip(label: "Adj", value: "\(EnergyFormat.balanceText(report.avgDeficitCorrected7d)) kcal/d")
                        chip(label: pctLabel, value: pctText)
                    }
                }
                if let warning = report.complianceWarning {
                    Text("⚠ \(warning)").font(.footnote).foregroundStyle(JIColor.reduced)
                        .accessibilityLabel("Warning: \(warning)")
                        .accessibilityIdentifier("energy.hero.complianceWarning")
                }
            }
        }
    }

    private var isSurplus: Bool { (report.avgDeficitPct7d ?? 0) < 0 }
    private var pctLabel: String { isSurplus ? "Surplus %" : "Deficit %" }
    private var pctText: String {
        guard let pct = report.avgDeficitPct7d else { return "—" }
        return String(format: "%.1f%%", abs(pct))
    }

    private var numeralAndBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(EnergyFormat.balanceText(report.avgDeficitCorrected7d)) kcal/d")
                .font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(JIColor.text)
                .contentTransition(.numericText())
                .accessibilityLabel("Adjusted energy balance")
                .accessibilityValue("\(EnergyFormat.balanceText(report.avgDeficitCorrected7d)) kcal per day")
                .accessibilityIdentifier("energy.hero.balance")
            Text(report.avgDeficitCorrected7d == nil ? "—" : (isSurplus ? "surplus" : "deficit"))
                .font(.footnote).foregroundStyle(JIColor.muted)
            bar
        }
    }

    private var bar: some View {
        let magnitude = report.avgDeficitPct7d.map(abs)
        let fillFrac = min((magnitude ?? 0) / Self.aggressiveMaxPct, 1)
        let overSustainable = (magnitude ?? 0) > Self.sustainableMaxPct
        let barColor = isSurplus || overSustainable ? JIColor.reduced : JIColor.info
        let markerFrac = min(Self.sustainableMaxPct / Self.aggressiveMaxPct, 1)
        return GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5).fill(JIColor.control).frame(height: 10)
                RoundedRectangle(cornerRadius: 5).fill(barColor).frame(width: g.size.width * fillFrac, height: 10)
                Rectangle().fill(JIColor.nested).frame(width: 2, height: 10).offset(x: g.size.width * markerFrac)
            }
        }.frame(height: 10)
        .accessibilityLabel("Deficit against the sustainable zone")
        .accessibilityValue(pctText)
    }

    private func chip(label: String, value: String) -> some View {
        Surface(level: 2, radius: 12, padding: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption2.bold()).foregroundStyle(JIColor.muted).lineLimit(1)
                Text(value).font(.footnote.bold()).foregroundStyle(JIColor.text).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(label)
            .accessibilityValue(value)
        }
    }
}
