import Testing
@testable import JIPersistence

@Test func prefsPersistAndRemove() throws {
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    try prefs.set("today.tileOrder", ["hrv", "rhr", "sleep", "steps"])
    #expect(try prefs.get("today.tileOrder", as: [String].self) == ["hrv", "rhr", "sleep", "steps"])
    try prefs.remove("today.tileOrder")
    #expect(try prefs.get("today.tileOrder", as: [String].self) == nil)
}
