import Testing
@testable import JIPersistence

// The controller ruling on Task 11 implements `inMemory()` as a disposable temp-file
// `DatabasePool` (DatabasePool cannot open ":memory:" — it needs a real file for WAL).
// That makes independence between two `inMemory()` calls worth proving explicitly: each
// call must produce its own throwaway file/store, not share state.
@Test func inMemoryInstancesAreIndependent() throws {
    let a = PrefStore(db: try AppDatabase.inMemory())
    let b = PrefStore(db: try AppDatabase.inMemory())
    try a.set("only.in.a", "yes")
    #expect(try a.get("only.in.a", as: String.self) == "yes")
    #expect(try b.get("only.in.a", as: String.self) == nil)
}
