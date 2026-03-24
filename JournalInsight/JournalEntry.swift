//
//  JournalEntry.swift
//  JournalInsight
//
//  Created by Tobias Tensfeldt on 25.04.2025.
//

import Foundation
import SwiftData

// MARK: - Mood

enum Mood: String, CaseIterable, Identifiable, Codable {
    case great, good, okay, bad, terrible

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .great: return "😄"
        case .good: return "🙂"
        case .okay: return "😐"
        case .bad: return "😞"
        case .terrible: return "😢"
        }
    }

    var label: String {
        rawValue.capitalized
    }
}

// MARK: - Tag

@Model
class Tag {
    @Attribute(.unique) var name: String

    init(name: String) {
        self.name = name
    }
}

// MARK: - JournalEntry

@Model
class JournalEntry {
    var date: Date
    var text: String
    var duration: TimeInterval
    var moodRaw: String?
    var tags: [Tag]

    var mood: Mood? {
        get { moodRaw.flatMap { Mood(rawValue: $0) } }
        set { moodRaw = newValue?.rawValue }
    }

    init(date: Date, text: String, duration: TimeInterval, mood: Mood? = nil, tags: [Tag] = []) {
        self.date = date
        self.text = text
        self.duration = duration
        self.moodRaw = mood?.rawValue
        self.tags = tags
    }
}
