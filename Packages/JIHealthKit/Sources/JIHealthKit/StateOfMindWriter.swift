#if canImport(HealthKit)
import Foundation
import HealthKit

/// B-24 P1: one Mind check-in reduced to exactly what may leave the sealed store for Apple
/// Health — the day and the mood's valence. Stress, energy, dosed and the free-text note are
/// deliberately NOT representable here (the ADHD-med signal stays on device).
///
/// JIHealthKit does not depend on JIPersistence (no GRDB in this graph), so the app maps
/// `CheckIn` -> `MoodMirrorEntry` with `valence = checkIn.mood?.valence`.
public struct MoodMirrorEntry: Sendable, Equatable {
    /// Check-in day, `yyyy-MM-dd` (local).
    public var date: String
    /// `Mood.valence` (-1 ... 1); nil when the check-in has no mood.
    public var valence: Double?
    /// The check-in's `updatedAt`; becomes `HKMetadataKeySyncVersion` (epoch seconds).
    public var updatedAt: Date

    public init(date: String, valence: Double?, updatedAt: Date) {
        self.date = date
        self.valence = valence
        self.updatedAt = updatedAt
    }
}

/// B-24 P1: a State of Mind sample as read back from the store (for the P3 sim proof and tests).
public struct StateOfMindReadBack: Sendable, Equatable {
    public var syncIdentifier: String?
    public var syncVersion: Int?
    public var valence: Double
    public var isDailyMood: Bool
    public var date: Date

    public init(syncIdentifier: String?, syncVersion: Int?, valence: Double, isDailyMood: Bool, date: Date) {
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
        self.valence = valence
        self.isDailyMood = isDailyMood
        self.date = date
    }
}

/// Read-back seam for State of Mind samples. Default is empty so existing `HealthStoreWriting`
/// fakes keep compiling; `RealHealthStore` answers with an `HKSampleQuery`.
public protocol StateOfMindReading: Sendable {
    func stateOfMindSamples(start: Date, end: Date) async throws -> [StateOfMindReadBack]
}

public extension HealthStoreWriting {
    func stateOfMindSamples(start: Date, end: Date) async throws -> [StateOfMindReadBack] {
        if let reader = self as? StateOfMindReading {
            return try await reader.stateOfMindSamples(start: start, end: end)
        }
        return []
    }
}

extension RealHealthStore: StateOfMindReading {
    public func stateOfMindSamples(start: Date, end: Date) async throws -> [StateOfMindReadBack] {
        let samples = try await readSamples(sampleType: HKSampleType.stateOfMindType(), start: start, end: end)
        return samples.compactMap { sample in
            guard let mind = sample as? HKStateOfMind else { return nil }
            return StateOfMindReadBack(
                syncIdentifier: mind.metadata?[HKMetadataKeySyncIdentifier] as? String,
                syncVersion: (mind.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue,
                valence: mind.valence,
                isDailyMood: mind.kind == .dailyMood,
                date: mind.startDate
            )
        }
    }
}

public enum StateOfMindWriteResult: Sendable, Equatable {
    /// Old sample (if any) deleted, new one saved.
    case written(syncIdentifier: String)
    /// No mood: any earlier mirror for that day removed, nothing saved.
    case removed(syncIdentifier: String)
    /// HealthKit unavailable (macOS, iPad without Health) — nothing touched.
    case unavailable
}

public enum StateOfMindWriterError: Error, Equatable {
    case invalidDate(String)
}

/// B-24 P1: mirrors a Mind check-in's mood into Apple Health as one `HKStateOfMind` per day
/// (`kind = .dailyMood`, valence = `Mood.valence`, no labels, no associations).
///
/// Idempotence: sync id `mind:<yyyy-MM-dd>` + `HKMetadataKeySyncVersion = updatedAt` epoch.
/// Upsert = delete every object carrying that sync id, then save — so a re-save the same day
/// replaces rather than duplicates. Authorization is a SEPARATE share request
/// (`requestAuthorization()`), never part of the backloader's type set, so the Garmin gate is
/// unchanged.
public struct StateOfMindWriter<Store: HealthStoreWriting>: Sendable {
    public static var sampleType: HKSampleType { HKSampleType.stateOfMindType() }
    public static var shareTypes: Set<HKSampleType> { [sampleType] }

    public let store: Store
    public let calendar: Calendar

    public init(store: Store, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    public static func syncIdentifier(for date: String) -> String { "mind:\(date)" }

    /// Asks only for State of Mind write access (the toggle-on path in the app).
    public func requestAuthorization() async throws {
        guard store.isHealthDataAvailable else { return }
        try await store.requestAuthorization(toShare: Self.shareTypes)
    }

    /// True when the user declined State of Mind sharing.
    public var isSharingDenied: Bool { store.allSharingDenied(Self.shareTypes) }

    /// Noon local on the check-in day — keeps the sample inside that calendar day in Health
    /// regardless of small time-zone shifts.
    public func sampleDate(for day: String) throws -> Date {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        else { throw StateOfMindWriterError.invalidDate(day) }
        return date
    }

    /// Builds the sample without touching the store (pure mapping, unit-tested).
    public func makeSample(_ entry: MoodMirrorEntry) throws -> HKStateOfMind? {
        guard let valence = entry.valence else { return nil }
        let date = try sampleDate(for: entry.date)
        let metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: Self.syncIdentifier(for: entry.date),
            HKMetadataKeySyncVersion: NSNumber(value: Int(entry.updatedAt.timeIntervalSince1970)),
        ]
        return HKStateOfMind(
            date: date,
            kind: .dailyMood,
            valence: max(-1, min(1, valence)),
            labels: [],
            associations: [],
            metadata: metadata
        )
    }

    /// Upsert for one day: delete by sync id, then save (or only delete when mood is nil).
    @discardableResult
    public func write(_ entry: MoodMirrorEntry) async throws -> StateOfMindWriteResult {
        guard store.isHealthDataAvailable else { return .unavailable }
        let id = Self.syncIdentifier(for: entry.date)
        let sample = try makeSample(entry)
        try await store.deleteObjects(sampleType: Self.sampleType, syncIdentifiers: [id])
        guard let sample else { return .removed(syncIdentifier: id) }
        try await store.save([sample])
        return .written(syncIdentifier: id)
    }
}
#endif
