// JournalInsight/Repositories/EntryRepository.swift
import Foundation
import SwiftData
import CryptoKit
import os

@MainActor
struct EntryRepository {
    private let context: ModelContext
    private let vault: VaultManager

    init(context: ModelContext, vault: VaultManager) {
        self.context = context
        self.vault = vault
    }

    /// Decrypt-and-return cached body for an entry. Throws `VaultError` if
    /// the user cancels biometric or the vault is osBlocked.
    func body(for entry: JournalEntry) async throws -> EntryBody {
        if let cached = Cache.shared.body(for: entry.persistentModelID) {
            return cached
        }
        let key = try await vault.sessionKey()
        do {
            let body = try EnvelopeCodec.decode(
                entry.bodyCipher,
                key: key,
                entryID: entry.id,
                schemaVersion: entry.schemaVersion
            )
            Cache.shared.set(body, for: entry.persistentModelID)
            return body
        } catch {
            Logger.crypto.error("decrypt entry=\(entry.id, privacy: .private(mask: .hash)) failed: \(error.localizedDescription, privacy: .public)")
            throw VaultError.decryptionFailed
        }
    }

    /// Create a new encrypted entry. Returns the inserted, saved JournalEntry.
    @discardableResult
    func create(
        date: Date,
        duration: TimeInterval,
        text: String,
        mood: Mood?,
        tags: [String]
    ) async throws -> JournalEntry {
        let key = try await vault.sessionKey()
        let entry = JournalEntry(date: date, text: "", duration: duration)
        entry.text = nil
        entry.moodRaw = nil
        entry.tags = []
        let body = EntryBody(text: text, mood: mood, tags: tags)
        let env = try EnvelopeCodec.encode(body, key: key, entryID: entry.id, schemaVersion: 1)
        entry.bodyCipher = env.cipher
        entry.nonce = env.nonce
        entry.schemaVersion = 1
        context.insert(entry)
        try context.save()
        Cache.shared.set(body, for: entry.persistentModelID)
        return entry
    }

    /// Update an existing entry's encrypted body.
    func update(
        _ entry: JournalEntry,
        text: String,
        mood: Mood?,
        tags: [String]
    ) async throws {
        let key = try await vault.sessionKey()
        let body = EntryBody(text: text, mood: mood, tags: tags)
        let env = try EnvelopeCodec.encode(body, key: key, entryID: entry.id, schemaVersion: 1)
        entry.bodyCipher = env.cipher
        entry.nonce = env.nonce
        entry.schemaVersion = 1
        try context.save()
        Cache.shared.set(body, for: entry.persistentModelID)
    }

    func delete(_ entry: JournalEntry) throws {
        Cache.shared.invalidate(entry.persistentModelID)
        context.delete(entry)
        try context.save()
    }

    /// Drop all cached plaintext. Called on vault lock events.
    func invalidateAll() async {
        Cache.shared.clear()
    }

    // MARK: - Cache (process-memory only, MainActor)

    @MainActor
    final class Cache {
        static let shared = Cache()
        private init() {
            // On every lock event from VaultManager, drop all cached plaintext.
            // Spec §1 mandates plaintext only lives in memory between unlock and lock.
            NotificationCenter.default.addObserver(
                forName: .journalInsightVaultDidLock,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.storage.removeAll()
            }
        }
        private var storage: [PersistentIdentifier: EntryBody] = [:]

        func body(for id: PersistentIdentifier) -> EntryBody? { storage[id] }
        func set(_ body: EntryBody, for id: PersistentIdentifier) { storage[id] = body }
        func invalidate(_ id: PersistentIdentifier) { storage.removeValue(forKey: id) }
        func clear() { storage.removeAll() }
    }
}
