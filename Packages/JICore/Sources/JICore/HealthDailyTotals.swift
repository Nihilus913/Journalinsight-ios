import Foundation

/// B-57 W2 (B-73): one local calendar day of the Health totals JI reads for nutrition and energy.
/// `nil` means Health returned no samples for that type on that day. It is never 0 (XC rule 5).
public struct HealthDailyTotals: Codable, Sendable, Equatable {
    public var date: String
    public var basalKcal: Double?
    public var activeKcal: Double?
    public var dietaryKcal: Double?
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?

    public init(date: String, basalKcal: Double? = nil, activeKcal: Double? = nil, dietaryKcal: Double? = nil,
                proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil) {
        self.date = date; self.basalKcal = basalKcal; self.activeKcal = activeKcal; self.dietaryKcal = dietaryKcal
        self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG
    }

    /// True when Health returned anything at all for this day.
    public var hasAnyValue: Bool {
        [basalKcal, activeKcal, dietaryKcal, proteinG, carbsG, fatG].contains { $0 != nil }
    }
}

/// Seam over the on-device Health reader (`JIHealthKit.HKDailyTotalsReader`), so JIFeatures can
/// test against a fake. `days` local calendar days ending TODAY (inclusive), oldest first, one
/// entry per day.
public protocol HealthDailyTotalsProviding: Sendable {
    func dailyTotals(days: Int) async throws -> [HealthDailyTotals]
}
