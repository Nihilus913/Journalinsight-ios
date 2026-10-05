import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W-FIX-P2 RG-27 — the next set number is max(set_index)+1, never `count+1` (a deleted middle set
/// must not make the next set reuse an existing number).
@MainActor @Suite(.serialized) struct StrengthSetIndexTests {
    let hub = StrengthFakeHub()
    let db: AppDatabase
    let store: StrengthSessionLogStore

    init() throws {
        db = try AppDatabase.inMemory()
        store = StrengthSessionLogStore(db: db)
    }

    let bench = StrengthLogLift(exerciseId: 7, exerciseKey: "Barbell Bench Press", sets: 3, repsTarget: "8",
                                currentKg: 50, stepKg: 2.5, nextKg: 50)

    @Test func deleteMiddleThenLogGivesSetOneThreeFour() throws {
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        let m = StrengthLogViewModel(lifts: [bench], sessionId: 1, sessionName: "Upper A", store: store, outbox: Outbox(db: db),
                                     provider: hub, prefs: PrefStore(db: db), today: { "2026-10-03" }, now: { t })
        for _ in 1...3 { m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 8) }
        #expect(m.cards[0].sets.map(\.setIndex) == [1, 2, 3])
        m.deleteSet(m.cards[0].sets[1])
        #expect(m.cards[0].nextSetIndex == 4)
        m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 8)
        #expect(m.cards[0].sets.map(\.setIndex).sorted() == [1, 3, 4])
        #expect(Set(m.cards[0].sets.map(\.setIndex)).count == m.cards[0].sets.count)
    }
}
