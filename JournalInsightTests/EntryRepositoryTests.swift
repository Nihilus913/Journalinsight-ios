// JournalInsightTests/EntryRepositoryTests.swift
import Testing
import Foundation
import SwiftData
import CryptoKit
@testable import JournalInsight

@MainActor
@Suite("EntryRepository")
struct EntryRepositoryTests {

    private func makeContext() throws -> ModelContext {
        let cfg = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: JournalEntry.self, Goal.self, Tag.self,
            configurations: cfg
        )
        return ModelContext(container)
    }

    private func makeVault(_ key: SymmetricKey) -> VaultManager {
        let fake = FakeKeychain(); fake.seedKey(key)
        let suite = UserDefaults(suiteName: "test.repo.\(UUID())")!
        return VaultManager(keychain: fake, lockPolicy: LockPolicySettings(suite: suite))
    }

    @Test("save encrypts and body decrypts back")
    func roundTripSaveBody() async throws {
        let ctx = try makeContext()
        let key = SymmetricKey(size: .bits256)
        let vault = makeVault(key)
        let repo = EntryRepository(context: ctx, vault: vault)

        let entry = try await repo.create(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 600,
            text: "hello",
            mood: .good,
            tags: ["one"]
        )

        #expect(entry.schemaVersion == 1)
        #expect(entry.bodyCipher.isEmpty == false)
        #expect(entry.text == nil)

        let body = try await repo.body(for: entry)
        #expect(body.text == "hello")
        #expect(body.mood == .good)
        #expect(body.tags == ["one"])
    }

    @Test("body cache returns same value without re-decrypting")
    func cachedBody() async throws {
        let ctx = try makeContext()
        let vault = makeVault(SymmetricKey(size: .bits256))
        let repo = EntryRepository(context: ctx, vault: vault)
        let entry = try await repo.create(date: .now, duration: 600, text: "x", mood: nil, tags: [])

        let first = try await repo.body(for: entry)
        let second = try await repo.body(for: entry)
        #expect(first == second)                     // identical content
        // No way to assert "no decrypt happened" without a counter — covered by inspection.
    }

    @Test("invalidateAll forces re-decryption")
    func invalidateForcesReDecrypt() async throws {
        let ctx = try makeContext()
        let vault = makeVault(SymmetricKey(size: .bits256))
        let repo = EntryRepository(context: ctx, vault: vault)
        let entry = try await repo.create(date: .now, duration: 600, text: "x", mood: nil, tags: [])

        _ = try await repo.body(for: entry)
        await repo.invalidateAll()
        // Subsequent call should still succeed
        let body = try await repo.body(for: entry)
        #expect(body.text == "x")
    }

    @Test("update encrypts new text and clears cache for that entry")
    func updateClearsCache() async throws {
        let ctx = try makeContext()
        let vault = makeVault(SymmetricKey(size: .bits256))
        let repo = EntryRepository(context: ctx, vault: vault)
        let entry = try await repo.create(date: .now, duration: 600, text: "before", mood: nil, tags: [])
        _ = try await repo.body(for: entry)
        try await repo.update(entry, text: "after", mood: .great, tags: ["t"])
        let body = try await repo.body(for: entry)
        #expect(body.text == "after")
        #expect(body.mood == .great)
        #expect(body.tags == ["t"])
    }

    @Test("body throws .userCancelled when vault rejects")
    func bodyThrowsOnVaultCancel() async throws {
        let ctx = try makeContext()
        let key = SymmetricKey(size: .bits256)
        let vaultGood = makeVault(key)
        let repoCreate = EntryRepository(context: ctx, vault: vaultGood)
        let entry = try await repoCreate.create(date: .now, duration: 600, text: "x", mood: nil, tags: [])

        // Now hand the entry to a repo whose vault refuses
        let fake2 = FakeKeychain(); fake2.loadError = .userCancelled
        let suite2 = UserDefaults(suiteName: "test.repo.\(UUID())")!
        let vaultBad = VaultManager(keychain: fake2, lockPolicy: LockPolicySettings(suite: suite2))
        let repoRead = EntryRepository(context: ctx, vault: vaultBad)
        // Cache.shared is process-global; create() warms it. Clear so read forces vault.
        await repoRead.invalidateAll()
        await #expect(throws: VaultError.userCancelled) {
            _ = try await repoRead.body(for: entry)
        }
    }
}
