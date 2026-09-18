import Foundation
import Testing
@testable import JIPersistence

// Port of `mobile/__tests__/lib/behaviorLogStore.test.ts` (6 tests) + the Swift-only undo path.
// The RN suite runs against an in-memory `cache` table; here the same `PrefStore` seam runs
// against a disposable `AppDatabase.inMemory()`.

private func makeStore(db: AppDatabase? = nil) throws -> (BehaviorLogStore, AppDatabase) {
    let db = try db ?? AppDatabase.inMemory()
    return (BehaviorLogStore(prefs: PrefStore(db: db)), db)
}

@Test func keyFormatMatchesRN() {
    #expect(BehaviorLogStore.key(for: "2026-08-31") == "behavior_log.v1.2026-08-31")
}

@Test func unseenDateReturnsEmptyMap() throws {
    let (store, _) = try makeStore()
    #expect(try store.load(date: "2026-08-31") == [:])
}

@Test func recordingRoundTripsThroughLoad() throws {
    let (store, _) = try makeStore()
    try store.record(date: "2026-08-31", cardId: "no-pre-workout-fueling", answer: .yes)
    #expect(try store.load(date: "2026-08-31") == ["no-pre-workout-fueling": .yes])
}

@Test func secondCardAccumulatesSameDay() throws {
    let (store, _) = try makeStore()
    try store.record(date: "2026-08-31", cardId: "no-pre-workout-fueling", answer: .yes)
    let result = try store.record(date: "2026-08-31", cardId: "reflux-safe-carbs", answer: .no)
    let expected: DeckResponses = ["no-pre-workout-fueling": .yes, "reflux-safe-carbs": .no]
    #expect(result == expected)
    #expect(try store.load(date: "2026-08-31") == expected)
}

@Test func reAnsweringReplacesPriorAnswer() throws {
    let (store, _) = try makeStore()
    try store.record(date: "2026-08-31", cardId: "reflux-safe-carbs", answer: .no)
    try store.record(date: "2026-08-31", cardId: "reflux-safe-carbs", answer: .yes)
    #expect(try store.load(date: "2026-08-31") == ["reflux-safe-carbs": .yes])
}

@Test func calendarDaysAreIndependent() throws {
    let (store, _) = try makeStore()
    try store.record(date: "2026-08-30", cardId: "reflux-safe-carbs", answer: .no)
    #expect(try store.load(date: "2026-08-31") == [:])
    #expect(try store.load(date: "2026-08-30") == ["reflux-safe-carbs": .no])
}

@Test func survivesSimulatedRestartSameDb() throws {
    let (store, db) = try makeStore()
    try store.record(date: "2026-08-31", cardId: "no-pre-workout-fueling", answer: .no)
    let (cold, _) = try makeStore(db: db) // new store instance, same underlying file
    #expect(try cold.load(date: "2026-08-31") == ["no-pre-workout-fueling": .no])
}

@Test func persistedJSONIsPlaintextRNShape() throws {
    // No vault: the pref row must decode as a plain {cardId: "yes"|"no"} object, the exact
    // shape RN's setLocalPref writes, so the two apps could share one file.
    let (store, db) = try makeStore()
    try store.record(date: "2026-08-31", cardId: "reflux-safe-carbs", answer: .yes)
    let raw = try PrefStore(db: db).get(BehaviorLogStore.key(for: "2026-08-31"), as: [String: String].self)
    #expect(raw == ["reflux-safe-carbs": "yes"])
}

@Test func removeUndoesOneAnswerAndKeepsTheRest() throws {
    let (store, _) = try makeStore()
    try store.record(date: "2026-08-31", cardId: "no-pre-workout-fueling", answer: .yes)
    try store.record(date: "2026-08-31", cardId: "reflux-safe-carbs", answer: .no)
    let result = try store.remove(date: "2026-08-31", cardId: "reflux-safe-carbs")
    #expect(result == ["no-pre-workout-fueling": .yes])
    #expect(try store.load(date: "2026-08-31") == ["no-pre-workout-fueling": .yes])
}

@Test func removingLastAnswerDeletesTheDayKey() throws {
    let (store, db) = try makeStore()
    try store.record(date: "2026-08-31", cardId: "no-pre-workout-fueling", answer: .yes)
    try store.remove(date: "2026-08-31", cardId: "no-pre-workout-fueling")
    #expect(try store.load(date: "2026-08-31") == [:])
    #expect(try PrefStore(db: db).get(BehaviorLogStore.key(for: "2026-08-31"), as: DeckResponses.self) == nil)
}

@Test func removingUnknownCardIsANoOp() throws {
    let (store, _) = try makeStore()
    try store.record(date: "2026-08-31", cardId: "no-pre-workout-fueling", answer: .yes)
    #expect(try store.remove(date: "2026-08-31", cardId: "ghost") == ["no-pre-workout-fueling": .yes])
}
