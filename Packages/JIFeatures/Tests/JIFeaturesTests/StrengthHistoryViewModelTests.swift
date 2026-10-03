import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W-B38-A A-11 — History from the cache first, then the hub (merged on client ids).
@MainActor @Suite(.serialized) struct StrengthHistoryViewModelTests {
    let hub = StrengthFakeHub()
    let store: StrengthSessionLogStore
    init() throws { store = StrengthSessionLogStore(db: try AppDatabase.inMemory()) }

    func seedLocal(_ id: String, date: String, sets: [(String, Double, Int)]) throws {
        try store.startSession(StrengthSessionLog(clientId: id, sessionName: "Upper A", date: date, startedAt: "\(date)T07:00:00Z"))
        for (i, s) in sets.enumerated() {
            try store.upsertSet(StrengthSetLog(clientId: "\(id)-\(i)", sessionClientId: id, exerciseKey: s.0, setIndex: i + 1,
                                               reps: s.2, weightKg: s.1, performedAt: "\(date)T07:0\(i):00Z"))
        }
    }

    @Test func cacheRendersOfflineGroupedByExercise() async throws {
        try seedLocal("a", date: "2026-10-01", sets: [("Barbell Bench Press", 50, 8), ("Barbell Bench Press", 50, 8), ("Barbell Row", 40, 10)])
        try seedLocal("b", date: "2026-10-03", sets: [("Barbell Bench Press", 52.5, 8)])
        try store.startSession(StrengthSessionLog(clientId: "empty", date: "2026-10-02", startedAt: "2026-10-02T07:00:00Z"))
        hub.online = false
        let m = StrengthHistoryViewModel(store: store, provider: hub, today: { "2026-10-03" })
        await m.load()
        #expect(m.entries.map(\.session.clientId) == ["b", "a"])     // newest first, empty session hidden
        #expect(m.entries[1].exercises.map(\.key) == ["Barbell Bench Press", "Barbell Row"])
        #expect(m.entries[1].exercises[0].sets.count == 2 && m.entries[1].setCount == 3)
        #expect(m.entries[0].exercises[0].topKg == 52.5)
        #expect(m.hubError != nil)
    }

    @Test func hubHistoryMergesWithoutDoubling() async throws {
        try seedLocal("a", date: "2026-10-01", sets: [("Barbell Bench Press", 50, 8)])
        hub.sessions["a"] = StrengthSessionOut(sessionLogId: 1, clientId: "a", date: "2026-10-01", startedAt: "2026-10-01T07:00:00Z")
        hub.sets["a-0"] = StrengthSetOut(clientId: "a-0", sessionLogId: 1, exerciseKey: "Barbell Bench Press", setIndex: 1, reps: 8, weightKg: 50, performedAt: "2026-10-01T07:00:00Z")
        hub.setOrder = ["a-0"]
        hub.sessions["w"] = StrengthSessionOut(sessionLogId: 2, clientId: "w", date: "2026-09-28", startedAt: "2026-09-28T07:00:00Z", endedAt: "2026-09-28T08:00:00Z")
        hub.sets["w-0"] = StrengthSetOut(clientId: "w-0", sessionLogId: 2, exerciseKey: "Barbell Row", setIndex: 1, reps: 10, weightKg: 40, performedAt: "2026-09-28T07:10:00Z")
        hub.setOrder.append("w-0")
        let m = StrengthHistoryViewModel(store: store, provider: hub, today: { "2026-10-03" })
        await m.load()
        #expect(m.loadedFromHub && m.hubError == nil)
        #expect(m.entries.map(\.session.clientId) == ["a", "w"])
        #expect(m.entries[0].setCount == 1)                              // not doubled
        #expect(m.entries[1].session.isComplete && m.entries[1].session.remoteId == 2)
    }

    @Test func noProviderIsCacheOnly() async throws {
        try seedLocal("a", date: "2026-10-01", sets: [("Plank", 0, 1)])
        let m = StrengthHistoryViewModel(store: store, provider: nil, today: { "2026-10-03" })
        await m.load()
        #expect(m.entries.count == 1 && !m.loadedFromHub)
    }

    @Test func dateTitleIsADayNotAStamp() {
        #expect(StrengthHistoryView.dateTitle("2026-10-03").contains("3"))
        #expect(StrengthHistoryView.dateTitle("garbage") == "garbage")
    }
}
