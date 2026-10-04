import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

/// W-FIX13 F-3 — the three strength-logger bugs from the W-B38-A review:
/// (a) the "pending sync" note clears when the Outbox drains (also by another drainer),
/// (b) "Last time" never shows today's own sets, (c) a dumbbell is per-hand weight, no bar.
@MainActor @Suite(.serialized) struct Fix13L3StrengthTests {
    let hub = StrengthFakeHub()
    let db: AppDatabase
    let prefs: PrefStore
    let outbox: Outbox
    let store: StrengthSessionLogStore
    let clock = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        db = try AppDatabase.inMemory()
        prefs = PrefStore(db: db); outbox = Outbox(db: db); store = StrengthSessionLogStore(db: db)
    }

    let bench = StrengthLogLift(exerciseId: 7, exerciseKey: "Barbell Bench Press", sets: 3, repsTarget: nil,
                                currentKg: nil, stepKg: nil, nextKg: nil)
    let curl = StrengthLogLift(exerciseId: 11, exerciseKey: "DB Biceps Curl", sets: 3, repsTarget: "10",
                               currentKg: 10, stepKg: 1, nextKg: 10)

    func model(_ lifts: [StrengthLogLift]) -> StrengthLogViewModel {
        let t = clock
        return StrengthLogViewModel(lifts: lifts, sessionId: 1, sessionName: "Upper A", store: store,
                                    outbox: outbox, provider: hub, prefs: prefs, today: { "2026-10-03" }, now: { t })
    }

    // (a)
    @Test func pendingNoteClearsWhenTheOutboxDrains() async throws {
        hub.online = false
        let m = model([bench])
        m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 8)
        await m.sync()
        #expect(m.syncNote != nil)
        hub.online = true
        // The app-wide drainer (its own StrengthOutbox over the same queue) delivers the rows.
        await StrengthOutbox(outbox: outbox, provider: hub).drainOnce()
        #expect(m.pendingCount == 0)
        #expect(m.syncNote == nil)
    }

    @Test func pendingNoteClearsWhenAnOverlappingPassDeliveredEverything() async {
        hub.online = false
        let m = model([bench])
        m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 8)
        await m.sync()
        #expect(m.syncNote != nil)
        hub.online = true
        await m.sync()
        #expect(m.syncNote == nil)
    }

    // (b)
    @Test func lastTimeExcludesTodaysSetsAndShowsTheEarlierSession() async throws {
        // Today's session was logged on this phone and reached the hub.
        let m0 = model([bench])
        let today = try #require(m0.logSet(exerciseKey: "Barbell Bench Press", weightKg: 55, reps: 5))
        await m0.sync()
        #expect(hub.sets[today.clientId] != nil)
        // The hub also has the 09-28 session (no copy on this phone).
        hub.sessions["s0928"] = StrengthSessionOut(sessionLogId: 99, clientId: "s0928", date: "2026-09-28", startedAt: "2026-09-28T07:00:00Z")
        hub.sets["old"] = StrengthSetOut(clientId: "old", sessionLogId: 99, exerciseKey: "Barbell Bench Press", setIndex: 1,
                                         reps: 10, weightKg: 47.5, performedAt: "2026-09-28T07:05:00Z")
        hub.setOrder.append("old")
        // The hub's last-sets is the newest session = today's.
        hub.lastSetsAnswer["Barbell Bench Press"] = [try #require(hub.sets[today.clientId])]
        let m = model([bench])
        await m.load()
        #expect(m.cards[0].lastTime.map(\.clientId) == ["old"])
        #expect(m.cards[0].lastTime.first?.weightKg == 47.5)
    }

    // (c)
    @Test func dumbbellIsPerHandPlatesWithNoBar() {
        let m = model([bench, curl])
        #expect(StrengthLoad.of("DB Biceps Curl") == .dumbbell)
        #expect(StrengthLoad.of("Dumbbell Shoulder Press") == .dumbbell)
        #expect(StrengthLoad.of("Barbell Bench Press") == .barbell)
        // 22.5 kg per hand: 11.25 per side of each dumbbell, from the default inventory (two pairs of
        // 10 → one pair per dumbbell), never "22.5 kg on a 20 kg bar".
        #expect(m.plates(for: 22.5, exerciseKey: "DB Biceps Curl") == [10, 1.25])
        #expect(m.plates(for: 22.5, exerciseKey: "Barbell Bench Press") == [1.25])   // the barbell keeps its 20 kg bar
        #expect(m.plates(for: 52.5, exerciseKey: "Barbell Bench Press") == [15, 1.25])
        let calc = PlateCalculatorViewModel(totalKg: 22.5, inventory: .default, load: .dumbbell)
        #expect(calc.outcome == .plates([10, 1.25]))
        #expect(calc.headline == "22.5 kg per dumbbell")
        #expect(!calc.headline.contains("bar"))
    }

    @Test func dumbbellPlateMathSharesTheInventoryBetweenTwoHands() {
        // One pair of 10s cannot load both dumbbells with a 10 each side.
        #expect(PlateMath.perSideDumbbell(perHandKg: 20, pairs: [10]) == nil)
        #expect(PlateMath.perSideDumbbell(perHandKg: 20, pairs: [10, 10]) == [10])
        #expect(PlateMath.perSideDumbbell(perHandKg: 0, pairs: [10, 10]) == [])
        #expect(PlateMath.perSideDumbbell(perHandKg: .nan, pairs: [10, 10]) == nil)
    }
}
