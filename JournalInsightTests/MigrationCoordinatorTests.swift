// JournalInsightTests/MigrationCoordinatorTests.swift
import Testing
import Foundation
import SwiftData
import CryptoKit
@testable import JournalInsight

@MainActor
@Suite("MigrationCoordinator — counts")
struct MigrationCoordinatorCountTests {

    private func makeContext() throws -> ModelContext {
        let cfg = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: JournalEntry.self, Goal.self, Tag.self,
            configurations: cfg
        )
        return ModelContext(container)
    }

    @Test("pendingCount on empty context is 0")
    func emptyPending() throws {
        let ctx = try makeContext()
        #expect(try MigrationCoordinator.pendingCount(in: ctx) == 0)
    }

    @Test("pendingCount counts only schemaVersion == 0")
    func mixedPending() throws {
        let ctx = try makeContext()
        let v0 = JournalEntry(date: .now, text: "v0", duration: 600)        // schemaVersion = 0 by default
        let v1 = JournalEntry(date: .now, text: "v1", duration: 600); v1.schemaVersion = 1
        let q  = JournalEntry(date: .now, text: "q",  duration: 600); q.schemaVersion = -1
        ctx.insert(v0); ctx.insert(v1); ctx.insert(q)
        try ctx.save()
        #expect(try MigrationCoordinator.pendingCount(in: ctx) == 1)
        #expect(try MigrationCoordinator.quarantineCount(in: ctx) == 1)
    }
}

@MainActor
@Suite("MigrationCoordinator — run")
struct MigrationCoordinatorRunTests {

    private func makeContext() throws -> ModelContext {
        let cfg = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: JournalEntry.self, Goal.self, Tag.self,
            configurations: cfg
        )
        return ModelContext(container)
    }

    private func makeVault(seed: SymmetricKey) -> VaultManager {
        let fake = FakeKeychain()
        fake.seedKey(seed)
        let suite = UserDefaults(suiteName: "test.mc.\(UUID())")!
        return VaultManager(keychain: fake, lockPolicy: LockPolicySettings(suite: suite))
    }

    @Test("run encrypts all v0 rows and clears plaintext")
    func encryptsAll() async throws {
        let ctx = try makeContext()
        let key = SymmetricKey(size: .bits256)
        let vault = makeVault(seed: key)

        // Note: using non-shared Tag instances per-entry. SwiftData's implicit
        // forward-only @Relationship doesn't reliably support sharing a single
        // Tag across multiple parent entries; the plan's original test reused
        // tagA across e1 and e2 and would fail on the live store.
        let tagA1 = Tag(name: "a")
        let tagA2 = Tag(name: "a"); let tagB2 = Tag(name: "b")
        ctx.insert(tagA1); ctx.insert(tagA2); ctx.insert(tagB2)
        let e1 = JournalEntry(date: .now, text: "first", duration: 600, mood: .good, tags: [tagA1])
        let e2 = JournalEntry(date: .now, text: "second", duration: 300, mood: .okay, tags: [tagA2, tagB2])
        let e1ID = e1.id
        ctx.insert(e1); ctx.insert(e2)
        try ctx.save()

        var seenSteps: [(Int, Int)] = []
        try await MigrationCoordinator.run(in: ctx, vault: vault) { current, total in
            seenSteps.append((current, total))
        }

        #expect(try MigrationCoordinator.pendingCount(in: ctx) == 0)
        #expect(seenSteps.count == 2)

        // Plaintext cleared, ciphertext non-empty
        for entry in [e1, e2] {
            #expect(entry.text == nil)
            #expect(entry.moodRaw == nil)
            #expect(entry.tags.isEmpty)
            #expect(entry.bodyCipher.isEmpty == false)
            #expect(entry.schemaVersion == 1)
            // Decrypt and confirm contents
            let decoded = try EnvelopeCodec.decode(entry.bodyCipher, key: key, entryID: entry.id, schemaVersion: 1)
            if entry.id == e1ID {
                #expect(decoded.text == "first")
                #expect(decoded.mood == .good)
                #expect(decoded.tags == ["a"])
            } else {
                #expect(decoded.text == "second")
                #expect(decoded.mood == .okay)
                #expect(decoded.tags == ["a", "b"])
            }
        }

        // Tag rows deleted at end of run
        let remainingTags = try ctx.fetchCount(FetchDescriptor<JournalInsight.Tag>())
        #expect(remainingTags == 0)
    }

    @Test("run is idempotent — second call after partial completion does only remaining")
    func idempotent() async throws {
        let ctx = try makeContext()
        let key = SymmetricKey(size: .bits256)
        let vault = makeVault(seed: key)

        let e1 = JournalEntry(date: .now, text: "x", duration: 600)
        let e2 = JournalEntry(date: .now, text: "y", duration: 600)
        ctx.insert(e1); ctx.insert(e2)
        // Pre-encrypt e1 manually to simulate a partial run
        let body = EntryBody(text: "x", mood: nil, tags: [])
        let env = try EnvelopeCodec.encode(body, key: key, entryID: e1.id, schemaVersion: 1)
        e1.bodyCipher = env.cipher; e1.nonce = env.nonce; e1.schemaVersion = 1
        e1.text = nil; e1.moodRaw = nil; e1.tags = []
        try ctx.save()

        var stepCount = 0
        try await MigrationCoordinator.run(in: ctx, vault: vault) { _, _ in stepCount += 1 }
        #expect(stepCount == 1)                                      // only e2 remained
        #expect(try MigrationCoordinator.pendingCount(in: ctx) == 0)
    }

    @Test("run on empty store completes without progress callback")
    func emptyStore() async throws {
        let ctx = try makeContext()
        let vault = makeVault(seed: SymmetricKey(size: .bits256))
        var called = false
        try await MigrationCoordinator.run(in: ctx, vault: vault) { _, _ in called = true }
        #expect(called == false)
    }
}
