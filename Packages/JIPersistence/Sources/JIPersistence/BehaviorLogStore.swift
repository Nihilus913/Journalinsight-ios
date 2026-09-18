import Foundation

// W8-L2 (P-journal). Port of `mobile/src/data/behaviorLogStore.ts` (41 L): the on-device log of
// the behaviour deck's daily yes/no answers. RN keeps it in the shared `local_prefs` sqlite file
// under the per-day key `behavior_log.v1.<date>` via `getLocalPref`/`setLocalPref`; the Swift
// counterpart of that seam is `PrefStore` (the same `pref` table `WeeklyPlanStore`/`TodayGrid`
// persist through), keyed identically. NOT a table (Migrations.swift is frozen this wave), and
// NOT vaulted — the oracle never routes it through `htv`/FieldCipher — so the JSON is plaintext.
//
// Keyed per calendar day so a new day always starts every card fresh: there is no separate
// "reset" step, the date key itself IS the reset. History beyond today isn't read back anywhere
// yet; the per-day key lets a future reader walk dates without a migration.

/// One card's answer (oracle: `BehaviorAnswer = "yes" | "no"`). Raw values are the RN strings so
/// the persisted JSON is byte-compatible with what RN writes under the same key.
public enum BehaviorAnswer: String, Codable, Sendable, Equatable, CaseIterable {
    case yes
    case no
}

/// cardId -> the answer recorded for ONE calendar day (oracle: `DeckResponses`).
public typealias DeckResponses = [String: BehaviorAnswer]

public struct BehaviorLogStore: Sendable {
    private let prefs: PrefStore

    public init(prefs: PrefStore) { self.prefs = prefs }

    /// Verbatim `keyFor(date)` from the oracle.
    public static func key(for date: String) -> String { "behavior_log.v1.\(date)" }

    /// `loadBehaviorResponses(date)`: an unseen date is an empty map, never nil.
    public func load(date: String) throws -> DeckResponses {
        try prefs.get(Self.key(for: date), as: DeckResponses.self) ?? [:]
    }

    /// `recordBehaviorResponse(date, cardId, answer)`: read-modify-write; returns the resulting
    /// full day's map. Re-answering the same card the same day replaces its prior answer.
    @discardableResult
    public func record(date: String, cardId: String, answer: BehaviorAnswer) throws -> DeckResponses {
        var next = try load(date: date)
        next[cardId] = answer
        try prefs.set(Self.key(for: date), next)
        return next
    }

    /// Undo (Swift-only, the W8 card's "undo removes it"): drops one card's answer for `date` so
    /// `orderDeck` puts the card back into the deck. Removing the last answer deletes the key
    /// outright so the day reads back exactly like an unseen one.
    @discardableResult
    public func remove(date: String, cardId: String) throws -> DeckResponses {
        var next = try load(date: date)
        next.removeValue(forKey: cardId)
        if next.isEmpty {
            try prefs.remove(Self.key(for: date))
        } else {
            try prefs.set(Self.key(for: date), next)
        }
        return next
    }
}
