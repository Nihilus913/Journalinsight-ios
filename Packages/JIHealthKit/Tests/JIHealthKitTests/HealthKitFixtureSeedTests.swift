#if DEBUG && canImport(HealthKit)
import CoreLocation
import Foundation
import HealthKit
import Testing
@testable import JIHealthKit

/// W-OFFLINE2 OFF2-2: the DEBUG `-seed-healthkit-fixture` seed — 35 nights of sleep + HRV
/// (SDNN/RMSSD) + RHR, 14 days of steps, 5 workouts (2 runs with route-less distance, 1 strength,
/// 2 walks), every object tagged (`JIDebugSeed` + a `ji-fixture:` sync id) and written once.
@Suite struct HealthKitFixtureSeedTests {
    /// A store that remembers what was saved, so a second run sees the first run's sync ids.
    final class RecordingStore: HealthStoreWriting, @unchecked Sendable {
        var isHealthDataAvailable = true
        private(set) var saved: [HKObject] = []
        private(set) var authRequested: Set<HKSampleType> = []
        func requestAuthorization(toShare types: Set<HKSampleType>) async throws { authRequested.formUnion(types) }
        func existingSyncVersions(sampleType: HKSampleType, start: Date, end: Date) async throws -> [String: Int] {
            var out: [String: Int] = [:]
            for case let s as HKSample in saved where s.sampleType == sampleType && s.endDate >= start && s.startDate <= end {
                if let id = s.metadata?[HKMetadataKeySyncIdentifier] as? String { out[id] = 1 }
            }
            return out
        }
        func save(_ objects: [HKObject]) async throws { saved.append(contentsOf: objects) }
        func deleteObjects(sampleType: HKSampleType, syncIdentifiers: Set<String>) async throws {}
        func deleteObjects(sampleType: HKSampleType, start: Date, end: Date, where shouldDelete: @Sendable (HKSample) -> Bool) async throws -> Int { 0 }
        func add(_ samples: [HKSample], to workout: HKWorkout) async throws {}
        func insertRoute(_ locations: [CLLocation], for workout: HKWorkout, metadata: [String: Any]) async throws {}
    }

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }
    /// 2026-10-07 12:00 Berlin.
    static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 12))!

    private func samples(_ objects: [HKObject], _ kind: HKReadKind) -> [HKSample] {
        guard let type = kind.sampleType else { return [] }
        return objects.compactMap { $0 as? HKSample }.filter { $0.sampleType == type }
    }

    @Test func launchFlagIsRead() {
        #expect(HealthKitFixtureSeed.isRequested(["app", "-seed-healthkit-fixture"]))
        #expect(!HealthKitFixtureSeed.isRequested(["app"]))
    }

    @Test func sampleCounts() {
        let objects = HealthKitFixtureSeed.objects(now: Self.now, calendar: Self.calendar)
        let sleep = samples(objects, .sleepAnalysis)
        let inBed = sleep.compactMap { $0 as? HKCategorySample }.filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }
        #expect(inBed.count == 35)
        #expect(sleep.count == 35 * 5)   // in bed + core/deep/rem/core per night
        #expect(samples(objects, .hrvSDNN).count == 35)
        if HKReadKind.hrvRMSSDTypeAvailable { #expect(samples(objects, .hrvRMSSD).count == 35) }
        #expect(samples(objects, .restingHeartRate).count == 35)
        #expect(samples(objects, .stepCount).count == 14)
        let workouts = objects.compactMap { $0 as? HKWorkout }
        #expect(workouts.count == 5)
        #expect(workouts.filter { $0.workoutActivityType == .running }.count == 2)
        #expect(workouts.filter { $0.workoutActivityType == .traditionalStrengthTraining }.count == 1)
        #expect(workouts.filter { $0.workoutActivityType == .walking }.count == 2)
        // Runs carry distance with no route (none is ever inserted).
        for run in workouts where run.workoutActivityType == .running {
            #expect((run.totalDistance?.doubleValue(for: .meter()) ?? 0) > 0)
        }
    }

    @Test func everyObjectIsTaggedAndNeverInTheFuture() {
        let objects = HealthKitFixtureSeed.objects(now: Self.now, calendar: Self.calendar)
        for case let s as HKSample in objects {
            #expect(s.metadata?[AppleWorkoutFilter.debugSeedMetadataKey] as? Bool == true)
            let id = s.metadata?[HKMetadataKeySyncIdentifier] as? String
            #expect(id?.hasPrefix(HealthKitFixtureSeed.syncPrefix) == true)
            // Never read back as a hub backload (`workout:` prefix is the backloader's).
            #expect(!AppleWorkoutFilter.isHubBackload(fromThisApp: true, syncIdentifier: id))
            #expect(s.endDate <= Self.now)
        }
        let ids = objects.compactMap { ($0 as? HKSample)?.metadata?[HKMetadataKeySyncIdentifier] as? String }
        #expect(Set(ids).count == ids.count)
    }

    @Test func todaysNamedValues() {
        let objects = HealthKitFixtureSeed.objects(now: Self.now, calendar: Self.calendar)
        let today = Self.calendar.startOfDay(for: Self.now)
        let steps = samples(objects, .stepCount).compactMap { $0 as? HKQuantitySample }
            .filter { Self.calendar.isDate($0.startDate, inSameDayAs: today) }
        #expect(steps.map { $0.quantity.doubleValue(for: .count()) } == [HealthKitFixtureSeed.todaySteps])
        let asleep = samples(objects, .sleepAnalysis).compactMap { $0 as? HKCategorySample }
            .filter { Self.calendar.isDate($0.endDate, inSameDayAs: today) && $0.value != HKCategoryValueSleepAnalysis.inBed.rawValue }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        #expect(asleep == HealthKitFixtureSeed.lastNightAsleepMinutes * 60)
    }

    @Test func secondRunIsIdempotent() async throws {
        let store = RecordingStore()
        let first = try await HealthKitFixtureSeed.run(store: store, now: Self.now, calendar: Self.calendar)
        let total = HealthKitFixtureSeed.objects(now: Self.now, calendar: Self.calendar).count
        #expect(first.written == total && first.skipped == 0)
        #expect(!store.authRequested.isEmpty)
        let second = try await HealthKitFixtureSeed.run(store: store, now: Self.now, calendar: Self.calendar)
        #expect(second.written == 0 && second.skipped == total)
        #expect(store.saved.count == total)
    }

    @Test func noHealthDataIsANoOp() async throws {
        let store = RecordingStore()
        store.isHealthDataAvailable = false
        let report = try await HealthKitFixtureSeed.run(store: store, now: Self.now, calendar: Self.calendar)
        #expect(report.written == 0 && store.saved.isEmpty)
    }

    /// Release guard: the seed and its app launcher compile only under `#if DEBUG`, and the app's
    /// call site sits inside a `#if DEBUG` block — a Release build never contains them.
    @Test func compiledOutOfRelease() throws {
        let pkg = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let repo = pkg.deletingLastPathComponent().deletingLastPathComponent()
        for url in [pkg.appendingPathComponent("Sources/JIHealthKit/HealthKitFixtureSeed.swift"),
                    repo.appendingPathComponent("App/Debug/HealthKitFixtureSeeder.swift")] {
            let text = try String(contentsOf: url, encoding: .utf8)
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            #expect(lines.first?.hasPrefix("#if DEBUG") == true, "\(url.lastPathComponent)")
            #expect(lines.last == "#endif", "\(url.lastPathComponent)")
        }
        let app = try String(contentsOf: repo.appendingPathComponent("App/RootTabView.swift"), encoding: .utf8)
        guard let call = app.range(of: "HealthKitFixtureSeeder.seedIfRequested()") else {
            Issue.record("call site missing"); return
        }
        let before = app[..<call.lowerBound]
        let opened = before.ranges(of: "#if DEBUG").last?.lowerBound
        let closed = before.ranges(of: "#endif").last?.lowerBound
        #expect(opened != nil && (closed == nil || closed! < opened!))
    }
}
#endif
