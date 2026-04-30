// JournalInsight/Vault/EntryBody.swift
import Foundation

/// In-memory plaintext shape of a journal entry. Never persisted directly;
/// only used as input to / output from `EnvelopeCodec`.
///
/// **Schema stability:** this struct's JSON encoding is the at-rest plaintext
/// inside every AES-GCM envelope. Adding new optional fields is safe (decoder
/// ignores unknown keys, old ciphertext still decodes). **Renaming or removing
/// a field will break decryption of every historical entry** — bump the
/// envelope schemaVersion and add a migration path instead.
struct EntryBody: Codable, Sendable, Equatable {
    var text: String
    var mood: Mood?
    var tags: [String]

    init(text: String, mood: Mood? = nil, tags: [String] = []) {
        self.text = text
        self.mood = mood
        self.tags = tags
    }
}
