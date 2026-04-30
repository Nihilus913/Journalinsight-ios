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
                // Quarantine-mark + plaintext-clearance in its own do/catch.
                //
                // Spec §1 mandates plaintext only ever lives in process memory. A quarantined
                // row that retained text/moodRaw/tags would (a) survive on disk in the
                // SwiftData store, (b) replicate to CloudKit as plaintext, (c) be readable
                // by any future tool that fetches the row. We accept the data-preservation
                // cost: a row whose source data couldn't even be JSON-encoded was likely
                // already corrupted, and the user cannot recover it from the encrypted store
                // either. The schemaVersion = -1 marker is what surfaces the row for any
                // future "review quarantined entries" affordance.
                //
                // If the quarantine-mark write itself fails, we still attempt to nil the
                // plaintext (best-effort defense-in-depth) and leave schemaVersion at 0 so
                // the next run() retries.
                do {
                    try ctx.transaction {
                        entry.schemaVersion = -1
                        entry.text = nil
                        entry.moodRaw = nil
                        entry.tags = []
                    }
                } catch {
                    Logger.migration.error(
                        "quarantine-mark also failed entry=\(entry.id, privacy: .private(mask: .hash)) reason=\(error.localizedDescription, privacy: .public)"
                    )
                    // Defense-in-depth: try to clear plaintext even if the version mark failed.
                    try? ctx.transaction {
                        entry.text = nil
                        entry.moodRaw = nil
                        entry.tags = []
                    }
                }
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
