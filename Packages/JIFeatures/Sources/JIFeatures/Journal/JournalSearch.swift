import Foundation
import JIPersistence

/// Ported verbatim from `mobile/src/journal/search.ts` (E13-1). Three independent axes (free-text
/// query, mood, tag) combine with AND semantics. `nonisolated` — see `JournalStreak`'s doc comment.
public nonisolated struct EntryFilters: Sendable, Equatable {
    public var query: String
    public var mood: Mood?
    public var tag: String?
    public nonisolated init(query: String = "", mood: Mood? = nil, tag: String? = nil) {
        self.query = query; self.mood = mood; self.tag = tag
    }
    public nonisolated static let empty = EntryFilters()
}

public nonisolated enum JournalSearch {
    public static func hasActiveFilters(_ filters: EntryFilters) -> Bool {
        !filters.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || filters.mood != nil
            || filters.tag != nil
    }

    public static func filterEntries(_ entries: [Entry], _ filters: EntryFilters) -> [Entry] {
        let query = filters.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            if let mood = filters.mood, entry.mood != mood.rawValue { return false }
            if let tag = filters.tag, !entry.tags.contains(tag) { return false }
            if !query.isEmpty, !entry.text.lowercased().contains(query) { return false }
            return true
        }
    }
}
