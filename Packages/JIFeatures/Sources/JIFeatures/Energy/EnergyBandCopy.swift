import Foundation
import JICore
import JICompute
import JIDesign

/// B-73: what the Energy screen knows from the phone's own band service (`EnergyBandService`):
/// the user's band + balance, the 7-day Health burn, and the Health-side reason word. `none` =
/// no service (tests, previews without one): every slot falls back to the hub report path.
public nonisolated struct EnergyBandState: Equatable, Sendable {
    public var result: EnergyBandResult?
    public var burn: EnergyBurnWindow?
    /// "Not in Health yet" / "Calibrating" / nil (burn known).
    public var reason: String?
    /// The user's kcal target (nil = "Set your goal").
    public var targetKcal: Double?

    public init(result: EnergyBandResult? = nil, burn: EnergyBurnWindow? = nil, reason: String? = nil, targetKcal: Double? = nil) {
        self.result = result; self.burn = burn; self.reason = reason; self.targetKcal = targetKcal
    }

    public static let none = EnergyBandState()
}

/// B-73: the Energy board's (2 Monitor/06) band strings, built from the band. Pure, so the copy
/// is tested without rendering. The kcal target is always the user's own; no default number ever
/// appears here (an unset goal reads "Set your goal"). The "How we calculate" steps stay
/// `energyHowWeCalculateSteps` (W-FIX4 PF-09 intake lineage), with the band rule updated there.
public nonisolated enum EnergyBandCopy {
    public static let noMedicalNote = JIExplainers.energyBalanceNote

    /// The 7-day balance (eaten − burned), signed like the board: "-500", "+120", "0"; "—" without.
    public static func heroValue(_ r: EnergyBandResult?) -> String {
        guard let balance = r?.balanceKcal else { return "—" }
        if balance == 0 { return "0" }
        return balance > 0 ? "+\(balance)" : "-\(-balance)"
    }

    /// The class line under the numeral. `reason` is the service's Health-side word.
    public static func heroReason(result r: EnergyBandResult?, reason: String?) -> String {
        if let cls = r?.balanceClass { return cls.label }
        if let r, !r.calibrating { return JIMissingReason.noData.rawValue }   // burn known, no food on complete days
        if let reason { return reason }
        return r == nil ? MacroGoals.setGoalCopy : JIMissingReason.noData.rawValue
    }

    public static func sentence(_ r: EnergyBandResult?) -> String? {
        guard let r, let cls = r.balanceClass else { return nil }
        let band = "\(r.bandLowKcal)–\(r.bandHighKcal) kcal a day"
        switch cls {
        case .onPlan: return "You are eating inside your plan band of \(band)."
        case .deepDeficit: return "You are eating below your plan band of \(band)."
        case .lightDeficit: return "You are eating above your plan band of \(band), still under what you burn."
        case .surplus: return "You are eating more than you burn."
        }
    }

    /// "≈ 480 kcal under what you burn": the gap between the user's target and the 7-day burn.
    /// Information only; nil while calibrating or without a goal.
    public static func impliedDeficit(_ r: EnergyBandResult?) -> String? {
        r?.impliedDeficitKcal.map(EnergyBand.impliedDeficitText)
    }

    /// (total, resting, active) for the "What you burn" card. Needs no goal.
    public static func burn(_ w: EnergyBurnWindow?) -> (total: String, resting: String, active: String) {
        guard let w, let total = w.burnKcal, let basal = w.basalKcal, let active = w.activeKcal else { return ("—", "—", "—") }
        return ("\(total)", "\(basal)", "\(active)")
    }

    /// The "This week" header: "Plan 1800 kcal", or "Set your goal".
    public static func planHeader(targetKcal: Double?) -> String {
        guard let t = targetKcal, t.isFinite, t > 0 else { return MacroGoals.setGoalCopy }
        return "Plan \(Int(t.rounded())) kcal"
    }

    /// "The band settles after a full week of Apple Health data." until 7 complete days exist.
    public static func settleNote(_ w: EnergyBurnWindow?) -> String? {
        (w?.settled ?? false) ? nil : MacroGoals.bandSettleNote
    }

    /// Step 4 of "How we calculate": the plan band is the user's own target ± 100.
    public static let bandRuleStep = HowWeCalculateStep(
        title: "Deficit or surplus",
        body: "Your plan band is the daily kcal target you set in Goals, ± \(EnergyBand.halfWidthKcal) kcal. JI never picks that number for you. Inside the band reads On plan. Below it: Deep deficit. Above it: Light deficit, and above what you burn: Surplus."
    )
}
