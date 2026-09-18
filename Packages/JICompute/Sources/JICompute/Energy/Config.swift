import Foundation

/// Every threshold/coefficient `app/nutrition/energy.py` hard-codes at module
/// scope, lifted into an injectable value (the Python module has no config
/// object — `EnergyConfig.default` IS the Python module's constant set, and the
/// goldens are generated against exactly these numbers).
///
/// Port of `mobile/src/compute/energy/types.ts::EnergyConfig` +
/// `energy.ts::DEFAULT_ENERGY_CONFIG`.
public nonisolated struct EnergyConfig: Sendable, Equatable {
    /// Legacy fallback multiplier when `kcalBurnedActive` is unavailable.
    public let garminTdeeCorrection: Double
    /// Garmin's BMR runs ~+425 kcal/day high (≈ Mifflin ×1.2, double-counting
    /// baseline activity). Anchor: Katch-McArdle from measured lean mass ≡
    /// smart-scale BMR within 0.15% (audit 2026-07-22).
    public let bmrAnchorKcal: Double
    /// Report compliance gate: minimum days with both intake and total kcal.
    public let minTrackingDays: Int
    /// Energy density of body-mass change (kcal per kg).
    public let kcalPerKg: Double
    /// Toby's chosen pace 2026-08-17: 0.5 kg/wk.
    public let deficitTargetKcal: Double
    /// Below this many tracked days, `trailingTdee` falls back to the additive
    /// model (returns nil).
    public let minEmpiricalTrackedDays: Int
    /// Muscle preservation in deficit — docs/research/energy-balance-sport-performance.md.
    public let proteinGPerKgFFM: Double
    /// 2026-08-18: lowered from 0.8 so the one static macro target can carry the
    /// training-day carb load; still above the ~0.5 g/kg ACSM/IOC EFA floor.
    public let fatMinGPerKgBW: Double
    /// kcal/kg FFM/day — RED-S screening line.
    public let leaThreshold: Double
    /// `classifyDeficit` cutoffs — research doc S2.2.
    public let deficitMildMaxPct: Double
    public let deficitModerateMaxPct: Double
    public let deficitAggressiveMaxPct: Double

    public init(
        garminTdeeCorrection: Double,
        bmrAnchorKcal: Double,
        minTrackingDays: Int,
        kcalPerKg: Double,
        deficitTargetKcal: Double,
        minEmpiricalTrackedDays: Int,
        proteinGPerKgFFM: Double,
        fatMinGPerKgBW: Double,
        leaThreshold: Double,
        deficitMildMaxPct: Double,
        deficitModerateMaxPct: Double,
        deficitAggressiveMaxPct: Double
    ) {
        self.garminTdeeCorrection = garminTdeeCorrection
        self.bmrAnchorKcal = bmrAnchorKcal
        self.minTrackingDays = minTrackingDays
        self.kcalPerKg = kcalPerKg
        self.deficitTargetKcal = deficitTargetKcal
        self.minEmpiricalTrackedDays = minEmpiricalTrackedDays
        self.proteinGPerKgFFM = proteinGPerKgFFM
        self.fatMinGPerKgBW = fatMinGPerKgBW
        self.leaThreshold = leaThreshold
        self.deficitMildMaxPct = deficitMildMaxPct
        self.deficitModerateMaxPct = deficitModerateMaxPct
        self.deficitAggressiveMaxPct = deficitAggressiveMaxPct
    }

    /// The live Python constants (`app/nutrition/energy.py`, 2026-08-18).
    public static let `default` = EnergyConfig(
        garminTdeeCorrection: 0.85,
        bmrAnchorKcal: 1642.0,
        minTrackingDays: 4,
        kcalPerKg: 7700,
        deficitTargetKcal: 550,
        minEmpiricalTrackedDays: 14,
        proteinGPerKgFFM: 2.5,
        fatMinGPerKgBW: 0.6,
        leaThreshold: 30.0,
        deficitMildMaxPct: 15,
        deficitModerateMaxPct: 22,
        deficitAggressiveMaxPct: 28
    )
}
