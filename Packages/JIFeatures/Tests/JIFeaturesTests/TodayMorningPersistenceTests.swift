import Testing
import Foundation
import JICore
import JIPersistence
@testable import JIFeatures

@Suite struct TodayMorningPersistenceTests {
    @MainActor private func fixtureMorning() throws -> MorningResponse {
        try #require(NativeFixtureStore.decode(fixtureMorningJSON, as: MorningResponse.self))
    }
    @MainActor private func model(prefs: PrefStore?) throws -> TodayViewModel {
        let cache = OfflineCache(db: try AppDatabase.inMemory())
        let m = TodayViewModel(provider: MockDataProvider(), cache: cache, prefs: prefs)
        m.setMorningForTesting(try fixtureMorning())
        return m
    }
    @Test @MainActor func startsAtDecideAndPersistsPerDate() throws {
        let db = try AppDatabase.inMemory(); let prefs = PrefStore(db: db)
        let m = try model(prefs: prefs)
        #expect(m.morningState == .decide)
        m.morningEvent(.gateResponded); m.morningEvent(.coachAcknowledged)
        #expect(m.morningState == .day)
        #expect(try prefs.get("today.morning.2026-09-21", as: TodayMorningState.self) == .day)
        let again = try model(prefs: prefs)
        #expect(again.morningState == .day)   // round trip
    }
    @Test @MainActor func newVerdictDateResetsToDecide() throws {
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        let m = try model(prefs: prefs)
        m.morningEvent(.gateResponded)
        var next = try fixtureMorning()
        next.verdictDate = "2026-09-22"
        m.setMorningForTesting(next)
        #expect(m.morningState == .decide)
    }
    @Test @MainActor func staleVerdictKeepsReachedState() throws {
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        let m = try model(prefs: prefs)
        m.morningEvent(.gateResponded)
        var same = try fixtureMorning()
        same.isStale = true
        m.setMorningForTesting(same)          // same verdictDate → same key
        #expect(m.morningState == .coach)
    }
    @Test @MainActor func noPrefStoreFallsBackToMemory() throws {
        let m = try model(prefs: nil)
        m.morningEvent(.gateResponded)
        #expect(m.morningState == .coach)
    }
    @Test @MainActor func fixtureMorningStateIsSetWithoutPersisting() throws {
        #expect(TodayViewModel.fixture()?.morningState == .day)
        #expect(TodayViewModel.fixture(morningState: .decide)?.morningState == .decide)
        #expect(TodayViewModel.fixture(morningState: .coach)?.morningState == .coach)
    }
}
