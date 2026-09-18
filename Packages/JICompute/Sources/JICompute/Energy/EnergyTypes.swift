import Foundation

/// `classify_deficit`'s label set (`app/nutrition/energy.py`). Raw values are
/// the Python strings verbatim — they cross the wire and reach the UI.
public nonisolated enum DeficitClass: String, Codable, Sendable, Equatable, CaseIterable {
    case surplus
    case mild
    case moderate
    case aggressive
    case dangerous
}

/// Mirrors `app/nutrition/models.py::DailyEnergyBalance` (field names
/// camelCased, shapes unchanged).
public nonisolated struct DailyEnergyBalance: Sendable, Equatable {
    public let date: String
    public let kcalConsumed: Double?
    public let tdeeRaw: Double?
    public let tdeeCorrected: Double?
    /// Positive = deficit, negative = surplus.
    public let deficitRaw: Double?
    public let deficitCorrected: Double?
    public let deficitPctRaw: Double?
    public let deficitPctCorrected: Double?
    public let deficitClass: DeficitClass?
    public let mealsLogged: Int?

    public init(
        date: String,
        kcalConsumed: Double?,
        tdeeRaw: Double?,
        tdeeCorrected: Double?,
        deficitRaw: Double?,
        deficitCorrected: Double?,
        deficitPctRaw: Double?,
        deficitPctCorrected: Double?,
        deficitClass: DeficitClass?,
        mealsLogged: Int?
    ) {
        self.date = date
        self.kcalConsumed = kcalConsumed
        self.tdeeRaw = tdeeRaw
        self.tdeeCorrected = tdeeCorrected
        self.deficitRaw = deficitRaw
        self.deficitCorrected = deficitCorrected
        self.deficitPctRaw = deficitPctRaw
        self.deficitPctCorrected = deficitPctCorrected
        self.deficitClass = deficitClass
        self.mealsLogged = mealsLogged
    }
}

/// `derive_goals`'s return dict, camelCased.
///
/// Python returns `int`s here (`round(x)` with no ndigits); the values are
/// carried as `Double` because that is what the TS oracle does and what every
/// downstream arithmetic step expects — `pythonRound(_:0)` never yields `-0.0`,
/// so the int semantics survive.
public nonisolated struct DeriveGoalsResult: Sendable, Equatable {
    public let intakeKcal: Double
    public let proteinG: Double?
    public let fatG: Double?
    public let carbsG: Double?

    public init(intakeKcal: Double, proteinG: Double?, fatG: Double?, carbsG: Double?) {
        self.intakeKcal = intakeKcal
        self.proteinG = proteinG
        self.fatG = fatG
        self.carbsG = carbsG
    }
}

/// The report-level aggregate of `summarizeEnergyDays` — the pure tail of
/// `app/nutrition/queries.py::compute_energy_balance` (that function itself is
/// DB-bound and out of this port).
public nonisolated struct EnergySummary: Sendable, Equatable {
    public let avgDeficitRaw7d: Double?
    public let avgDeficitCorrected7d: Double?
    public let avgDeficitPct7d: Double?
    /// Days with both intake and total kcal present.
    public let trackingDays: Int
    /// `trackingDays >= config.minTrackingDays`.
    public let compliant: Bool
    /// nil when compliant.
    public let complianceWarning: String?

    public init(
        avgDeficitRaw7d: Double?,
        avgDeficitCorrected7d: Double?,
        avgDeficitPct7d: Double?,
        trackingDays: Int,
        compliant: Bool,
        complianceWarning: String?
    ) {
        self.avgDeficitRaw7d = avgDeficitRaw7d
        self.avgDeficitCorrected7d = avgDeficitCorrected7d
        self.avgDeficitPct7d = avgDeficitPct7d
        self.trackingDays = trackingDays
        self.compliant = compliant
        self.complianceWarning = complianceWarning
    }
}
