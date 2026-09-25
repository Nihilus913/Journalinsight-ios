#if canImport(HealthKit)
import Foundation
import HealthKit

/// B-57 W2 (B-73): daily cumulative sums over `[start, end)`, keyed by local day start.
/// `HKStatisticsCollectionQuery` with `.cumulativeSum` merges overlapping sources by the user's
/// Health "Data Sources" order. That is what stops Apple Watch energy and JI's own backloaded
/// Garmin energy from being added twice (Review Focus 1). Never sum raw samples for these types.
public protocol HealthStoreStatistics: Sendable {
    func dailySums(for type: HKQuantityType, unit: HKUnit, start: Date, end: Date, calendar: Calendar) async throws -> [Date: Double]
}

extension RealHealthStoreReader: HealthStoreStatistics {
    public func dailySums(for type: HKQuantityType, unit: HKUnit, start: Date, end: Date, calendar: Calendar) async throws -> [Date: Double] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum,
                anchorDate: start, intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    // "No data" / not authorized is an empty answer, not a failure (rule 5: renders "—").
                    if let code = (error as? HKError)?.code, code == .errorNoData || code == .errorAuthorizationNotDetermined {
                        continuation.resume(returning: [:]); return
                    }
                    continuation.resume(throwing: error); return
                }
                var out: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let sum = stats.sumQuantity() { out[calendar.startOfDay(for: stats.startDate)] = sum.doubleValue(for: unit) }
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }
}

/// The on-device reader for nutrition + energy: six source-merged daily sums over the last
/// `days` local days (today included), laid on `HKSampleWindow`'s calendar grid, oldest first.
///
/// Its row is `HKDailyTotalsReader.Day`, a field-for-field twin of JICore's
/// `HealthDailyTotals` (Task A2, landed by another lane after this one): the
/// `HealthDailyTotalsProviding` conformance maps `Day` → `HealthDailyTotals` 1:1 once A2 exists.
public struct HKDailyTotalsReader: Sendable {
    /// One local calendar day. `nil` = Health returned no samples for that type that day (not
    /// granted yet, or nothing logged) — never 0 (XC rule 5).
    public struct Day: Sendable, Equatable {
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

    private let store: any HealthStoreStatistics
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        store: any HealthStoreStatistics,
        calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store; self.calendar = calendar; self.now = now
    }

    /// `days` local calendar days ending TODAY (inclusive), oldest first, one entry per day.
    public func dailyRows(days: Int) async throws -> [Day] {
        try await fetch(days: days)
    }

    /// Off the caller's actor (2026-09-23 lesson: HealthKit reads on the MainActor froze the app).
    @concurrent
    private func fetch(days: Int) async throws -> [Day] {
        let window = HKSampleWindow(windowDays: days, now: now(), calendar: calendar)
        let calendar = self.calendar
        let store = self.store
        func sums(_ kind: HKReadKind, _ unit: HKUnit) async throws -> [String: Double] {
            guard let type = kind.sampleType as? HKQuantityType else { return [:] }
            let raw = try await store.dailySums(for: type, unit: unit, start: window.start, end: window.end, calendar: calendar)
            return Dictionary(raw.map { (HKSampleWindow.isoDay($0.key, calendar: calendar), $0.value) }, uniquingKeysWith: +)
        }
        let basal = try await sums(.basalEnergy, .kilocalorie())
        let active = try await sums(.activeEnergy, .kilocalorie())
        let dietary = try await sums(.dietaryEnergy, .kilocalorie())
        let protein = try await sums(.dietaryProtein, .gram())
        let carbs = try await sums(.dietaryCarbs, .gram())
        let fat = try await sums(.dietaryFat, .gram())
        return window.days.map { key in
            Day(date: key, basalKcal: basal[key], activeKcal: active[key], dietaryKcal: dietary[key],
                proteinG: protein[key], carbsG: carbs[key], fatG: fat[key])
        }
    }
}
#endif
