import Foundation

/// B-73 (B-57 W2): the JI plan band. Pure, with no clock and no calendar (XC rule 8). The caller
/// passes local `"YYYY-MM-DD"` keys, `today` and the user's kcal TARGET (JICore
/// `KcalGoal.targetKcal`: the goal as typed, or goal − deficit when the user asked JI to subtract).
/// JI never picks the number: band = target ± 100, and nothing is subtracted here.
/// The Health part (burn, balance, implied deficit) follows the "complete day" rule, which lives
/// only here:
/// - burn is complete when resting AND active are both present and > 0 (a missing basal is a gap,
///   never a zero);
/// - balance also needs food > 0 ("a day with no food in Health is skipped, not counted as zero");
/// - today never counts ("today counts once it ends").
public nonisolated struct EnergyBandDay: Codable, Sendable, Equatable {
    public var date: String
    public var basalKcal: Double?
    public var activeKcal: Double?
    public var intakeKcal: Double?

    public init(date: String, basalKcal: Double? = nil, activeKcal: Double? = nil, intakeKcal: Double? = nil) {
        self.date = date; self.basalKcal = basalKcal; self.activeKcal = activeKcal; self.intakeKcal = intakeKcal
    }

    public var burnKcal: Double? {
        guard let basal = basalKcal, let active = activeKcal, basal > 0, active > 0 else { return nil }
        return basal + active
    }
}

public nonisolated enum EnergyBalanceClass: String, Codable, Sendable, Equatable, CaseIterable {
    case onPlan = "on_plan"
    case deepDeficit = "deep_deficit"
    case lightDeficit = "light_deficit"
    case surplus

    public var label: String {
        switch self {
        case .onPlan: "On plan"
        case .deepDeficit: "Deep deficit"
        case .lightDeficit: "Light deficit"
        case .surplus: "Surplus"
        }
    }
}

/// The 7-day Health burn. The burn fields are nil ("Calibrating") below `minCompleteDays`.
public nonisolated struct EnergyBurnWindow: Codable, Sendable, Equatable {
    public var completeDays: Int
    /// All `windowDays` days complete: "The band settles after a full week of Apple Health data."
    public var settled: Bool
    public var burnKcal: Int?
    public var basalKcal: Int?
    public var activeKcal: Int?

    public init(completeDays: Int, settled: Bool, burnKcal: Int?, basalKcal: Int?, activeKcal: Int?) {
        self.completeDays = completeDays; self.settled = settled
        self.burnKcal = burnKcal; self.basalKcal = basalKcal; self.activeKcal = activeKcal
    }

    public var calibrating: Bool { burnKcal == nil }
}

public nonisolated struct EnergyBandResult: Codable, Sendable, Equatable {
    public var targetKcal: Int
    public var bandLowKcal: Int
    public var bandHighKcal: Int
    public var burn: EnergyBurnWindow
    /// burn − target, shown as information only ("≈ 480 kcal under what you burn"). Negative = a
    /// surplus target. nil while calibrating.
    public var impliedDeficitKcal: Int?
    public var balanceKcal: Int?
    public var balanceDays: Int
    public var balanceClass: EnergyBalanceClass?

    public init(targetKcal: Int, bandLowKcal: Int, bandHighKcal: Int, burn: EnergyBurnWindow,
                impliedDeficitKcal: Int?, balanceKcal: Int?, balanceDays: Int, balanceClass: EnergyBalanceClass?) {
        self.targetKcal = targetKcal; self.bandLowKcal = bandLowKcal; self.bandHighKcal = bandHighKcal
        self.burn = burn; self.impliedDeficitKcal = impliedDeficitKcal
        self.balanceKcal = balanceKcal; self.balanceDays = balanceDays; self.balanceClass = balanceClass
    }

    public var burnKcal: Int? { burn.burnKcal }
    public var settled: Bool { burn.settled }
    public var calibrating: Bool { burn.calibrating }
}

public nonisolated enum EnergyBand {
    public static let windowDays = 7
    public static let halfWidthKcal = 100
    /// Below this many complete burn days the Health part is "Calibrating".
    public static let minCompleteDays = 3
    /// Sanity prompt thresholds (GoalsSetup): a subtract-a-deficit target more than this far
    /// below burn, or a goal already this far below burn, triggers "Does your goal already include a deficit?".
    public static let askGapKcal = 1000
    public static let askBelowBurnKcal = 300

    public static func band(targetKcal: Int) -> (low: Int, high: Int) {
        (targetKcal - halfWidthKcal, targetKcal + halfWidthKcal)
    }

    public static func impliedDeficit(burnKcal: Int, targetKcal: Int) -> Int { burnKcal - targetKcal }

    /// Rounded to the nearest 10. Information, never a verdict.
    public static func impliedDeficitText(_ kcal: Int) -> String {
        let r = Int((Double(kcal) / 10).rounded(.toNearestOrAwayFromZero)) * 10
        if r == 0 { return "≈ what you burn" }
        return r > 0 ? "≈ \(r) kcal under what you burn" : "≈ \(-r) kcal over what you burn"
    }

    /// Balance = eaten − burned (negative = deficit). The planned balance is target − burn; it is
    /// not clamped, so a surplus target is legal.
    public static func classify(balanceKcal: Int, targetBalanceKcal: Int) -> EnergyBalanceClass {
        if abs(balanceKcal - targetBalanceKcal) <= halfWidthKcal { return .onPlan }
        if balanceKcal > 0 { return .surplus }
        if balanceKcal < targetBalanceKcal - halfWidthKcal { return .deepDeficit }
        return .lightDeficit
    }

    /// The last `windowDays` keys strictly before `today`, oldest first. The reader supplies a
    /// full calendar grid, so these are the 7 calendar days before today.
    public static func window(_ days: [EnergyBandDay], today: String) -> [EnergyBandDay] {
        Array(days.filter { $0.date < today }.sorted { $0.date < $1.date }.suffix(windowDays))
    }

    public static func burnWindow(days: [EnergyBandDay], today: String) -> EnergyBurnWindow {
        let burnDays = window(days, today: today).filter { $0.burnKcal != nil }
        let settled = burnDays.count == windowDays
        guard burnDays.count >= minCompleteDays else {
            return EnergyBurnWindow(completeDays: burnDays.count, settled: settled, burnKcal: nil, basalKcal: nil, activeKcal: nil)
        }
        let n = Double(burnDays.count)
        return EnergyBurnWindow(
            completeDays: burnDays.count, settled: settled,
            burnKcal: roundKcal(burnDays.compactMap(\.burnKcal).reduce(0, +) / n),
            basalKcal: roundKcal(burnDays.compactMap(\.basalKcal).reduce(0, +) / n),
            activeKcal: roundKcal(burnDays.compactMap(\.activeKcal).reduce(0, +) / n)
        )
    }

    public static func compute(targetKcal: Double, days: [EnergyBandDay], today: String) -> EnergyBandResult {
        let target = roundKcal(targetKcal)
        let b = band(targetKcal: target)
        let burn = burnWindow(days: days, today: today)
        guard let burnKcal = burn.burnKcal else {
            return EnergyBandResult(targetKcal: target, bandLowKcal: b.low, bandHighKcal: b.high, burn: burn,
                                    impliedDeficitKcal: nil, balanceKcal: nil, balanceDays: 0, balanceClass: nil)
        }
        let foodDays = window(days, today: today).filter { $0.burnKcal != nil && ($0.intakeKcal ?? 0) > 0 }
        let balance: Int? = foodDays.isEmpty ? nil : roundKcal(
            foodDays.map { $0.intakeKcal! - $0.burnKcal! }.reduce(0, +) / Double(foodDays.count)
        )
        return EnergyBandResult(
            targetKcal: target, bandLowKcal: b.low, bandHighKcal: b.high, burn: burn,
            impliedDeficitKcal: impliedDeficit(burnKcal: burnKcal, targetKcal: target),
            balanceKcal: balance, balanceDays: foodDays.count,
            balanceClass: balance.map { classify(balanceKcal: $0, targetBalanceKcal: target - burnKcal) }
        )
    }

    /// GoalsSetup sanity prompt for a "subtract a deficit" goal. true when the resulting target sits
    /// more than `askGapKcal` below burn, or the goal itself is already more than `askBelowBurnKcal`
    /// below burn (it probably already includes the deficit). No burn → never ask.
    public static func shouldAskIfGoalIncludesDeficit(goalKcal: Double, deficitKcal: Double, burnKcal: Int?) -> Bool {
        guard let burnKcal else { return false }
        let target = goalKcal - max(0, deficitKcal)
        return Double(burnKcal) - target > Double(askGapKcal) || goalKcal < Double(burnKcal - askBelowBurnKcal)
    }

    private static func roundKcal(_ x: Double) -> Int { Int(x.rounded(.toNearestOrAwayFromZero)) }
}
