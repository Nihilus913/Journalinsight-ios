import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W-FIX-P2 RG-26 (B-52) — after Complete the logger takes no more sets: no orphan second session,
/// and the completed session's sets stay on the cards.
@MainActor @Suite(.serialized) struct LoggerAfterCompleteTests {
    let hub = StrengthFakeHub()
    let db: AppDatabase
    let store: StrengthSessionLogStore
    let outbox: Outbox
    let prefs: PrefStore

    init() throws {
        db = try AppDatabase.inMemory()
        prefs = PrefStore(db: db); outbox = Outbox(db: db); store = StrengthSessionLogStore(db: db)
    }

    let bench = StrengthLogLift(exerciseId: 7, exerciseKey: "Barbell Bench Press", sets: 3, repsTarget: "8",
                                currentKg: 50, stepKg: 2.5, nextKg: 50)

    func model() -> StrengthLogViewModel {
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        return StrengthLogViewModel(lifts: [bench], sessionId: 1, sessionName: "Upper A", store: store, outbox: outbox,
                                    provider: hub, prefs: prefs, today: { "2026-10-03" }, now: { t })
    }

    @Test func logAfterCompleteCreatesNoNewSession() async throws {
        let m = model()
        m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 8)
        m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 8)
        #expect(m.canLogSet)
        await m.complete()
        #expect(try #require(m.session).isComplete)
        let before = try store.sessions(from: "2026-10-03", to: "2026-10-03").count
        #expect(!m.canLogSet)
        #expect(m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 8) == nil)
        #expect(try store.sessions(from: "2026-10-03", to: "2026-10-03").count == before)
        #expect(before == 1)
        #expect(m.cards[0].sets.count == 2)   // completed sets stay on the card
        await m.sync()
        #expect(hub.sessions.count == 1)
    }
}
