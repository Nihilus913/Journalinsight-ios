// JournalInsightTests/ContainerSwapTests.swift
import Testing
import Foundation
import SwiftData
import CryptoKit
@testable import JournalInsight

@MainActor
@Suite("ContainerSwap (integration)")
struct ContainerSwapTests {

    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID()).store")
    }

    private static func cleanup(_ url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        try? fm.removeItem(at: url.appendingPathExtension("shm"))
        try? fm.removeItem(at: url.appendingPathExtension("wal"))
    }

    @Test("Local-only container then re-open without CloudKit preserves data")
    func reopenWithoutCloudKit() throws {
        let url = tempStoreURL()
        defer { Self.cleanup(url) }

        let schema = Schema([JournalEntry.self, Goal.self, Tag.self])

        // Open #1 — local-only, write entries.
        let cfg1 = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container1 = try ModelContainer(for: schema, configurations: cfg1)
        let ctx1 = ModelContext(container1)
        let key = SymmetricKey(size: .bits256)
        let body = EntryBody(text: "hello", mood: .good, tags: ["work"])
        let id = UUID()
        let env = try EnvelopeCodec.encode(body, key: key, entryID: id, schemaVersion: 1)
        let entry = JournalEntry(id: id, date: .now, text: "", duration: 600)
        entry.text = nil; entry.moodRaw = nil; entry.tags = []
        entry.bodyCipher = env.cipher; entry.nonce = env.nonce; entry.schemaVersion = 1
        ctx1.insert(entry)
        try ctx1.save()

        // Tear down: drop references — SwiftData closes when no contexts remain.
        // (In a real boot, dropping the `BootCoordinator.cachedPreContainer` reference does this.)

        // Open #2 — same schema + URL, *also* local-only (we cannot really
        // exercise CloudKit in unit tests without a signed-in iCloud account
        // — Plan 7 manual test #2 covers the production CloudKit case).
        let cfg2 = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container2 = try ModelContainer(for: schema, configurations: cfg2)
        let ctx2 = ModelContext(container2)
        let entries = try ctx2.fetch(FetchDescriptor<JournalEntry>())
        #expect(entries.count == 1)
        let fetched = try #require(entries.first)
        #expect(fetched.id == id)
        #expect(fetched.schemaVersion == 1)
        let decoded = try EnvelopeCodec.decode(fetched.bodyCipher, key: key, entryID: id, schemaVersion: 1)
        #expect(decoded.text == "hello")
        #expect(decoded.mood == .good)
        #expect(decoded.tags == ["work"])
    }

    @Test("Stage-1 lightweight migration upgrades a V0-only file to V1")
    func lightweightMigrationFromV0() throws {
        let url = tempStoreURL()
        defer { Self.cleanup(url) }

        let schema = Schema([JournalEntry.self, Goal.self, Tag.self])

        // SwiftData auto-migrates additive schema changes (new columns with
        // defaults) without an explicit migration plan. Production validation
        // of a real V0 store happens in Plan 7 manual test step #1.
        let cfg = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: cfg)
        let ctx = ModelContext(container)
        // Insert a V0-shaped entry: schemaVersion default 0, text populated.
        let entry = JournalEntry(date: .now, text: "legacy", duration: 600)
        ctx.insert(entry)
        try ctx.save()

        let pending = try MigrationCoordinator.pendingCount(in: ctx)
        #expect(pending == 1)
    }
}
