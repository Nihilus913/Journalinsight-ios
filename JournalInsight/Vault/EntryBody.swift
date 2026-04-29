// JournalInsight/Vault/EntryBody.swift
import Foundation

/// In-memory plaintext shape of a journal entry. Never persisted directly;
/// only used as input to / output from `EnvelopeCodec`.
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
