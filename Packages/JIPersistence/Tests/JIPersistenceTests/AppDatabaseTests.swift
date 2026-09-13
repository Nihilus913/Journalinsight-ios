import Foundation
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

@Test func excludedFromBackupFlagIsSetOnTheFileAndItsWalSiblings() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("journalinsight-backup-\(UUID().uuidString).sqlite")
    _ = try AppDatabase.open(at: url, excludedFromBackup: true)
    for suffix in ["", "-wal", "-shm"] {
        let sibling = URL(filePath: url.path + suffix)
        guard FileManager.default.fileExists(atPath: sibling.path) else { continue }
        #expect(try sibling.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true, "\(suffix)")
    }
    #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
}
