//
//  JournalEntry.swift
//  JournalInsight
//

import Foundation
import SwiftData

// MARK: - Mood

enum Mood: String, CaseIterable, Identifiable, Codable, Sendable {
    case great, good, okay, bad, terrible
    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .great:    return "😄"
        case .good:     return "🙂"
        case .okay:     return "😐"
        case .bad:      return "😞"
        case .terrible: return "😢"
        }
    }

    var label: String { rawValue.capitalized }
}

// MARK: - Tag (deprecated — kept temporarily for V0→V1 migration; v1.1 cleanup will delete the entity)

@Model
final class Tag {
    var name: String = ""
    init(name: String) { self.name = name }
}

// MARK: - JournalEntry

/// V1 schema. Plaintext fields (`text`, `moodRaw`, `tags`) remain in the schema
/// only so Stage-2 migration can read legacy V0 rows. Once Stage 2 has run on
/// every row (`schemaVersion == 1`), the plaintext fields are nil and the Tag
/// relationship is empty. The v1.1 cleanup migration removes them entirely.
@Model
final class JournalEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var duration: TimeInterval = 0

    // Encrypted payload (post-migration)
    var bodyCipher: Data = Data()
    var nonce: Data = Data()
    var schemaVersion: Int = 0

    // Legacy plaintext columns — read by Stage 2, then nilled.
    var text: String? = nil
    var moodRaw: String? = nil

    // Legacy relationship — read by Stage 2, then emptied.
    @Relationship var tags: [Tag] = []

    init(
        id: UUID = UUID(),
        date: Date,
        text: String,
        duration: TimeInterval,
        mood: Mood? = nil,
        tags: [Tag] = []
    ) {
        self.id = id
        self.date = date
        self.text = text
        self.duration = duration
        self.moodRaw = mood?.rawValue
        self.tags = tags
        // schemaVersion stays 0 until Stage 2 encrypts.
    }

    /// Decoded mood from legacy column (used only during Stage 2).
    var mood: Mood? {
        get { moodRaw.flatMap(Mood.init(rawValue:)) }
        set { moodRaw = newValue?.rawValue }
    }
}
