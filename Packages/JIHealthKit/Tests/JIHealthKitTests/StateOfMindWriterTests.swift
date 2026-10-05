#if canImport(HealthKit)
import CoreLocation
import Foundation
import HealthKit
import Testing
@testable import JIHealthKit

/// B-24 P1: in-memory store that logs every call in order and keeps saved samples, so upsert
/// (delete-by-sync-id then save) is observable as "still exactly one sample for the day".
final class MindFakeStore: HealthStoreWriting, StateOfMindReading, @unchecked Sendable {
    enum Call: Equatable { case auth(Set<String>), delete(String, Set<String>), save(Int) }
    var isHealthDataAvailable = true
    var denied = false
    private(set) var calls: [Call] = []
    private(set) var samples: [HKSample] = []

    func allSharingDenied(_ types: Set<HKSampleType>) -> Bool { denied }
    func requestAuthorization(toShare types: Set<HKSampleType>) async throws {
        calls.append(.auth(Set(types.map(\.identifier))))
    }
    func existingSyncVersions(sampleType: HKSampleType, start: Date, end: Date) async throws -> [String: Int] { [:] }
    func save(_ objects: [HKObject]) async throws {
        calls.append(.save(objects.count))
        samples.append(contentsOf: objects.compactMap { $0 as? HKSample })
    }
    func deleteObjects(sampleType: HKSampleType, syncIdentifiers: Set<String>) async throws {
        calls.append(.delete(sampleType.identifier, syncIdentifiers))
        samples.removeAll { $0.sampleType == sampleType && ($0.metadata?[HKMetadataKeySyncIdentifier] as? String).map(syncIdentifiers.contains) == true }
    }
    func deleteObjects(sampleType: HKSampleType, start: Date, end: Date, where shouldDelete: @Sendable (HKSample) -> Bool) async throws -> Int { 0 }
    func add(_ samples: [HKSample], to workout: HKWorkout) async throws {}
    func insertRoute(_ locations: [CLLocation], for workout: HKWorkout, metadata: [String: Any]) async throws {}

    func stateOfMindSamples(start: Date, end: Date) async throws -> [StateOfMindReadBack] {
        samples.compactMap { $0 as? HKStateOfMind }
            .filter { $0.startDate >= start && $0.startDate <= end }
            .map {
                StateOfMindReadBack(
                    syncIdentifier: $0.metadata?[HKMetadataKeySyncIdentifier] as? String,
                    syncVersion: ($0.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue,
                    valence: $0.valence, isDailyMood: $0.kind == .dailyMood, date: $0.startDate)
            }
    }
}

@Suite("B-24 StateOfMindWriter")
struct StateOfMindWriterTests {
    static let berlin: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()
    static let updated = Date(timeIntervalSince1970: 1_791_100_000)

    /// The `Mood.valence` table (JIPersistence/MindStore.swift) — great/good/okay/bad/terrible.
    static let moodValence: [(String, Double)] = [("great", 1), ("good", 0.5), ("okay", 0), ("bad", -0.5), ("terrible", -1)]

    func writer(_ store: MindFakeStore) -> StateOfMindWriter<MindFakeStore> {
        StateOfMindWriter(store: store, calendar: Self.berlin)
    }

    @Test("5 moods map to valence -1/-0.5/0/0.5/1 as dailyMood, no labels/associations", arguments: moodValence)
    func mapping(mood: String, valence: Double) throws {
        let sample = try #require(try writer(MindFakeStore()).makeSample(.init(date: "2026-10-04", valence: valence, updatedAt: Self.updated)))
        #expect(sample.valence == valence)
        #expect(sample.kind == .dailyMood)
        #expect(sample.labels.isEmpty)
        #expect(sample.associations.isEmpty)
    }

    @Test("sync id mind:<yyyy-MM-dd>, version = updatedAt epoch, date = noon local")
    func metadataAndDate() throws {
        #expect(StateOfMindWriter<MindFakeStore>.syncIdentifier(for: "2026-10-04") == "mind:2026-10-04")
        let sample = try #require(try writer(MindFakeStore()).makeSample(.init(date: "2026-10-04", valence: 0.5, updatedAt: Self.updated)))
        #expect(sample.metadata?[HKMetadataKeySyncIdentifier] as? String == "mind:2026-10-04")
        #expect((sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue == 1_791_100_000)
        let parts = Self.berlin.dateComponents([.year, .month, .day, .hour, .minute], from: sample.startDate)
        #expect(parts == DateComponents(year: 2026, month: 10, day: 4, hour: 12, minute: 0))
        #expect(sample.metadata?.keys.sorted() == [HKMetadataKeySyncIdentifier, HKMetadataKeySyncVersion].sorted())
    }

    @Test("upsert = exactly 1 delete by sync id, then 1 save")
    func upsertOrder() async throws {
        let store = MindFakeStore()
        let result = try await writer(store).write(.init(date: "2026-10-04", valence: 0.5, updatedAt: Self.updated))
        #expect(result == .written(syncIdentifier: "mind:2026-10-04"))
        #expect(store.calls == [.delete(HKSampleType.stateOfMindType().identifier, ["mind:2026-10-04"]), .save(1)])
    }

    @Test("re-save same day replaces: still 1 sample, new valence")
    func resaveSameDay() async throws {
        let store = MindFakeStore()
        let w = writer(store)
        try await w.write(.init(date: "2026-10-04", valence: 0.5, updatedAt: Self.updated))
        try await w.write(.init(date: "2026-10-04", valence: -0.5, updatedAt: Self.updated.addingTimeInterval(60)))
        let back = try await store.stateOfMindSamples(start: .distantPast, end: .distantFuture)
        #expect(back.count == 1)
        #expect(back.first?.valence == -0.5)
        #expect(back.first?.syncVersion == 1_791_100_060)
        // Another day is its own sample.
        try await w.write(.init(date: "2026-10-05", valence: 1, updatedAt: Self.updated))
        #expect(try await store.stateOfMindSamples(start: .distantPast, end: .distantFuture).count == 2)
    }

    @Test("nil mood: no save, earlier mirror for that day removed")
    func nilMoodRemoves() async throws {
        let store = MindFakeStore()
        let w = writer(store)
        try await w.write(.init(date: "2026-10-04", valence: 0.5, updatedAt: Self.updated))
        let result = try await w.write(.init(date: "2026-10-04", valence: nil, updatedAt: Self.updated))
        #expect(result == .removed(syncIdentifier: "mind:2026-10-04"))
        #expect(store.calls.filter { if case .save = $0 { true } else { false } }.count == 1)
        #expect(try await store.stateOfMindSamples(start: .distantPast, end: .distantFuture).isEmpty)
    }

    @Test("HealthKit unavailable: store untouched")
    func unavailable() async throws {
        let store = MindFakeStore()
        store.isHealthDataAvailable = false
        let w = writer(store)
        #expect(try await w.write(.init(date: "2026-10-04", valence: 1, updatedAt: Self.updated)) == .unavailable)
        try await w.requestAuthorization()
        #expect(store.calls.isEmpty)
    }

    @Test("separate share auth: only stateOfMind, not in the backloader type set")
    func separateAuth() async throws {
        let store = MindFakeStore()
        try await writer(store).requestAuthorization()
        #expect(store.calls == [.auth([HKSampleType.stateOfMindType().identifier])])
        #expect(!HealthKitBackloader.allSampleTypes.contains(HKSampleType.stateOfMindType()))
        store.denied = true
        #expect(writer(store).isSharingDenied)
    }

    @Test("invalid date throws, nothing written")
    func invalidDate() async {
        let store = MindFakeStore()
        await #expect(throws: StateOfMindWriterError.invalidDate("bogus")) {
            try await writer(store).write(.init(date: "bogus", valence: 1, updatedAt: Self.updated))
        }
        #expect(store.calls.isEmpty)
    }

    @Test("valence is clamped to -1...1")
    func clamp() throws {
        let w = writer(MindFakeStore())
        #expect(try w.makeSample(.init(date: "2026-10-04", valence: 3, updatedAt: Self.updated))?.valence == 1)
        #expect(try w.makeSample(.init(date: "2026-10-04", valence: -3, updatedAt: Self.updated))?.valence == -1)
    }

    @Test("protocol-extension read-back is empty for a store without the reading seam")
    func readBackDefault() async throws {
        let fake = FakeHealthStore()
        #expect(try await fake.stateOfMindSamples(start: .distantPast, end: .distantFuture).isEmpty)
    }
}
#endif
