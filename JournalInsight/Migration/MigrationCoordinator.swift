// JournalInsight/Migration/MigrationCoordinator.swift
import Foundation
import SwiftData
import CryptoKit
import os

@MainActor
struct MigrationCoordinator {

    /// Number of `JournalEntry` rows still at v0 plaintext (`schemaVersion == 0`).
    static func pendingCount(in ctx: ModelContext) throws -> Int {
        let predicate = #Predicate<JournalEntry> { $0.schemaVersion == 0 }
        let descriptor = FetchDescriptor<JournalEntry>(predicate: predicate)
        return try ctx.fetchCount(descriptor)
    }

    /// Number of rows that failed Stage-2 encryption and are quarantined (`schemaVersion == -1`).
    static func quarantineCount(in ctx: ModelContext) throws -> Int {
        let predicate = #Predicate<JournalEntry> { $0.schemaVersion == -1 }
        let descriptor = FetchDescriptor<JournalEntry>(predicate: predicate)
        return try ctx.fetchCount(descriptor)
    }

    /// Encrypts every `schemaVersion == 0` row in `ctx` using the master key
    /// fetched from `vault`. Each row's encryption is its own
    /// `ctx.transaction { }`, making a mid-run kill produce a consistent
    /// partial state that resumes cleanly on next launch.
    ///
    /// `progress` fires once per processed row with `(current, total)`.
    static func run(
        in ctx: ModelContext,
        vault: VaultManager,
        defaults: UserDefaults = .standard,
        progress: @MainActor (Int, Int) -> Void = { _, _ in }
    ) async throws {
        let pendingFetch = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.schemaVersion == 0 }
        )
        let pending = try ctx.fetch(pendingFetch)
        let total = pending.count
        guard total > 0 else { return }

        let key = try await vault.sessionKey()

        for (i, entry) in pending.enumerated() {
            do {
                try ctx.transaction {
                    let body = EntryBody(
                        text: entry.text ?? "",
                        mood: entry.mood,
                        tags: entry.tags.map(\.name)
                    )
                    let envelope = try EnvelopeCodec.encode(
                        body,
                        key: key,
                        entryID: entry.id,
                        schemaVersion: 1
                    )
                    entry.bodyCipher = envelope.cipher
                    entry.nonce      = envelope.nonce
                    entry.schemaVersion = 1
                    entry.text       = nil
                    entry.moodRaw    = nil
                    entry.tags       = []
                }
            } catch {
                Logger.migration.error(
                    "quarantine entry=\(entry.id, privacy: .private(mask: .hash)) reason=\(error.localizedDescription, privacy: .public)"
                )
                try ctx.transaction { entry.schemaVersion = -1 }
            }
            progress(i + 1, total)
        }

        // All rows processed — orphan Tag rows safe to delete.
        try ctx.transaction {
            let allTags = try ctx.fetch(FetchDescriptor<Tag>())
            for tag in allTags { ctx.delete(tag) }
        }

        defaults.set(1, forKey: StorageKeys.lastSuccessfulMigrationVersion)
    }
}
