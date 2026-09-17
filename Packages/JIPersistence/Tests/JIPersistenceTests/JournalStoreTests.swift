import Testing
import CryptoKit
@testable import JIPersistence
import JIVault

/// In-process fake `KeychainService` (own copy — `JIVaultTests`' `FakeKeychain` is not exported
/// across module boundaries) so this test file can drive a real `VaultManager` → `EnvelopeFieldCipher`
/// without touching the device Keychain.
final class FakeKeychainStore: KeychainService, @unchecked Sendable {
    private var key: SymmetricKey?
    func loadMasterKey() async throws -> SymmetricKey {
        guard let key else { throw KeychainError.itemNotFound }
        return key
    }
    func storeNewMasterKey() async throws -> SymmetricKey {
        let k = SymmetricKey(size: .bits256)
        key = k
        return k
    }
    func deleteMasterKey() async throws { key = nil }
}

@Suite struct JournalStoreTests {
    @Test func addThenListRoundTripsWithMoodAndTags() throws {
        let store = JournalStore(db: try AppDatabase.inMemory())
        let id = try store.addEntry(NewEntry(date: "2026-08-23", text: "hi", durationSec: 300, mood: "good", tags: ["work"]))
        #expect(id > 0)
        let list = try store.listEntries()
        #expect(list.count == 1)
        #expect(list[0].date == "2026-08-23")
        #expect(list[0].text == "hi")
        #expect(list[0].mood == "good")
        #expect(list[0].tags == ["work"])
        #expect(try store.allDates() == ["2026-08-23"])
        #expect(try store.allTags() == ["work"])
    }

    @Test func listEntriesReturnsNewestFirst() throws {
        let store = JournalStore(db: try AppDatabase.inMemory())
        try store.addEntry(NewEntry(date: "2026-08-20", text: "first", durationSec: 60, mood: "okay", tags: []))
        try store.addEntry(NewEntry(date: "2026-08-21", text: "second", durationSec: 60, mood: "okay", tags: []))
        let list = try store.listEntries()
        #expect(list.map(\.text) == ["second", "first"])
    }

    @Test func updateEntryRewritesFieldsAndRebuildsTags() throws {
        let store = JournalStore(db: try AppDatabase.inMemory())
        let id = try store.addEntry(NewEntry(date: "2026-08-23", text: "draft", durationSec: 60, mood: "bad", tags: ["work"]))
        try store.updateEntry(id: id, NewEntry(date: "2026-08-24", text: "final", durationSec: 120, mood: "great", tags: ["personal", "gratitude"]))
        let list = try store.listEntries()
        #expect(list.count == 1)
        #expect(list[0].date == "2026-08-24")
        #expect(list[0].text == "final")
        #expect(list[0].durationSec == 120)
        #expect(list[0].mood == "great")
        #expect(list[0].tags.sorted() == ["gratitude", "personal"])
        #expect(Set(try store.allTags()).isSuperset(of: ["work", "personal", "gratitude"]))
    }

    @Test func deleteEntryRemovesEntryAndTagLinks() throws {
        let store = JournalStore(db: try AppDatabase.inMemory())
        let keep = try store.addEntry(NewEntry(date: "2026-08-22", text: "keep me", durationSec: 60, mood: "okay", tags: ["daily"]))
        let gone = try store.addEntry(NewEntry(date: "2026-08-23", text: "delete me", durationSec: 60, mood: "okay", tags: ["daily"]))
        try store.deleteEntry(id: gone)
        let list = try store.listEntries()
        #expect(list.count == 1)
        #expect(list[0].id == keep)
        #expect(try store.allDates() == ["2026-08-22"])
    }

    @Test func withIdentityCipherRawColumnsAreThePlaintext() throws {
        let store = JournalStore(db: try AppDatabase.inMemory())
        let id = try store.addEntry(NewEntry(date: "2026-08-23", text: "plain text", durationSec: 60, mood: "good", tags: []))
        let raw = try store.rawColumns(id: id)
        #expect(raw?.text == "plain text")
        #expect(raw?.mood == "good")
    }

    @Test func withRealEnvelopeCipherRawColumnsAreCiphertextButReadsDecrypt() async throws {
        let vault = VaultManager(keychain: FakeKeychainStore())
        let cipher = try await vault.unlock()
        let store = JournalStore(db: try AppDatabase.inMemory(), cipher: cipher)
        let id = try store.addEntry(NewEntry(date: "2026-08-23", text: "secret text", durationSec: 60, mood: "bad", tags: ["private"]))

        let raw = try store.rawColumns(id: id)
        #expect(raw != nil)
        #expect(raw!.text != "secret text")
        #expect(raw!.mood != "bad")

        let list = try store.listEntries()
        #expect(list[0].text == "secret text")
        #expect(list[0].mood == "bad")
    }
}
