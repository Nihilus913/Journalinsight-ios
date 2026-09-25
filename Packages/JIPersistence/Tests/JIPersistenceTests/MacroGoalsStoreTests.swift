import Foundation
import Testing
import JICore
@testable import JIPersistence

@Test func firstLoadIsUnsetAndWritesNothing() throws {
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    let store = MacroGoalsStore(prefs: prefs)
    #expect(try store.load() == .unset)
    #expect(try prefs.get(MacroGoalsStore.key, as: MacroGoals.self) == nil)   // no seeding write
}

@Test func savedGoalsSurviveARelaunch() throws {
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    let edited = MacroGoals(kcal: KcalGoal(goalKcal: 1600, basis: .includesDeficit), proteinG: 170, carbsG: nil, fatG: 55)
    try MacroGoalsStore(prefs: prefs).save(edited)
    #expect(try MacroGoalsStore(prefs: prefs).load() == edited)   // a fresh store over the same DB = relaunch
}

@Test func corruptRowThrowsRatherThanSilentlyResetting() throws {
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    try prefs.set(MacroGoalsStore.key, "not a goals object")
    #expect(throws: (any Error).self) { try MacroGoalsStore(prefs: prefs).load() }
}
