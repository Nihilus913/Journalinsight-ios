#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
@testable import JIHealthKit

/// Fake statistics seam: returns canned day-start → value per type identifier and records the
/// unit asked for each type.
final class FakeStatistics: HealthStoreStatistics, @unchecked Sendable { // test-only; mutated from one task
    var sums: [String: [Date: Double]] = [:]
    var unitsAsked: [String: HKUnit] = [:]
    func dailySums(for type: HKQuantityType, unit: HKUnit, start: Date, end: Date, calendar: Calendar) async throws -> [Date: Double] {
        unitsAsked[type.identifier] = unit
        return sums[type.identifier] ?? [:]
    }
}

@Suite struct HKDailyTotalsReaderTests {
    static let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    static let now = ISO8601DateFormatter().date(from: "2026-09-24T10:00:00Z")!
    static func day(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso + "T00:00:00Z")! }
    static func id(_ k: HKReadKind) -> String { (k.sampleType as! HKQuantityType).identifier }

    @Test func buildsAFullOldestFirstGridWithNilGaps() async throws {
        let fake = FakeStatistics()
        fake.sums[Self.id(.basalEnergy)] = [Self.day("2026-09-23"): 1800]
        fake.sums[Self.id(.activeEnergy)] = [Self.day("2026-09-23"): 520.4, Self.day("2026-09-24"): 80]
        fake.sums[Self.id(.dietaryEnergy)] = [Self.day("2026-09-22"): 1750]
        fake.sums[Self.id(.dietaryProtein)] = [Self.day("2026-09-22"): 150]
        let reader = HKDailyTotalsReader(store: fake, calendar: Self.utc, now: { Self.now })

        let rows = try await reader.dailyRows(days: 8)

        #expect(rows.map(\.date) == ["2026-09-17", "2026-09-18", "2026-09-19", "2026-09-20", "2026-09-21", "2026-09-22", "2026-09-23", "2026-09-24"])
        #expect(rows[6] == HKDailyTotalsReader.Day(date: "2026-09-23", basalKcal: 1800, activeKcal: 520.4))
        #expect(rows[7] == HKDailyTotalsReader.Day(date: "2026-09-24", activeKcal: 80))
        #expect(rows[5].dietaryKcal == 1750)
        #expect(rows[5].proteinG == 150)
        #expect(rows[5].carbsG == nil)
        #expect(rows[0].hasAnyValue == false)   // no samples → nil, never 0
    }

    /// Review Focus 2: a kind that is not granted yet reads as no samples — every field nil,
    /// never 0 kcal, so Energy can say "— Not in Health yet".
    @Test func nothingGrantedGivesAllNilDaysNeverZero() async throws {
        let rows = try await HKDailyTotalsReader(store: FakeStatistics(), calendar: Self.utc, now: { Self.now }).dailyRows(days: 7)
        #expect(rows.count == 7)
        #expect(rows.allSatisfy { !$0.hasAnyValue })
    }

    @Test func asksKilocaloriesForEnergyAndGramsForMacros() async throws {
        let fake = FakeStatistics()
        _ = try await HKDailyTotalsReader(store: fake, calendar: Self.utc, now: { Self.now }).dailyRows(days: 1)
        for k in [HKReadKind.basalEnergy, .activeEnergy, .dietaryEnergy] { #expect(fake.unitsAsked[Self.id(k)] == .kilocalorie()) }
        for k in [HKReadKind.dietaryProtein, .dietaryCarbs, .dietaryFat] { #expect(fake.unitsAsked[Self.id(k)] == .gram()) }
    }

    /// Review Focus 1: burn must come from the source-merged statistics seam. The reader's only
    /// dependency is `HealthStoreStatistics`, so exactly the six types go through it.
    @Test func everyTotalGoesThroughTheStatisticsSeam() async throws {
        let fake = FakeStatistics()
        _ = try await HKDailyTotalsReader(store: fake, calendar: Self.utc, now: { Self.now }).dailyRows(days: 1)
        #expect(Set(fake.unitsAsked.keys) == Set([HKReadKind.basalEnergy, .activeEnergy, .dietaryEnergy, .dietaryProtein, .dietaryCarbs, .dietaryFat].map(Self.id)))
    }

    /// Review Focus 1 (source pin): the reader file sums with `.cumulativeSum` statistics and
    /// never runs a raw-sample query for these types.
    @Test func readerHasNoRawSamplePath() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JIHealthKit/Provider/HKDailyTotalsReader.swift")
        let src = try String(contentsOf: file, encoding: .utf8)
        #expect(src.contains("HKStatisticsCollectionQuery"))
        #expect(src.contains(".cumulativeSum"))
        #expect(!src.contains("HKSampleQuery("))
        #expect(!src.contains("HKAnchoredObjectQuery("))
        #expect(!src.contains("anchoredSamples("))
    }
}
#endif
