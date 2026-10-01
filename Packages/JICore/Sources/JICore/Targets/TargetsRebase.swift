import Foundation

// W-FIX11 H2-01 (S1, bug hunt 2026-10-01): saving one target PUT the phone's stale whole document
// and overwrote the hub's newer numbers (74 kg / 12000 steps), even from an unrelated Sleep save.
// A save is now a patch of the CHANGED keys: the edit remembers the document it started from
// (`base`), and the sender applies only what differs from `base` to a FRESH copy of the hub's
// document before the PUT. Granularity = one target (a goal, a limit field, a rule).

/// The outbox payload of a targets save: the edited document plus the document it was edited
/// from. `base == nil` = a whole document on purpose (the §5 first import, an older build's row).
public nonisolated struct TargetsEdit: Codable, Equatable, Sendable {
    public var document: TargetsDocument
    public var base: TargetsDocument?

    public init(document: TargetsDocument, base: TargetsDocument?) {
        self.document = document; self.base = base
    }

    /// A queued row's payload: an edit, or (older rows, the import) a bare document.
    public static func decodeOutbox(_ payload: Data) -> TargetsEdit? {
        if let edit = try? JSONDecoder().decode(TargetsEdit.self, from: payload) { return edit }
        guard let whole = try? JSONDecoder().decode(TargetsDocument.self, from: payload) else { return nil }
        return TargetsEdit(document: whole, base: nil)
    }

    /// This edit applied to `current` (the hub's fresh document, or the result of older edits).
    public func applied(to current: TargetsDocument) -> TargetsDocument {
        guard let base else { return document }
        return document.rebased(onto: current, from: base)
    }

    /// The edits of a queue applied in order to `hub` (nil = no hub copy needed: the newest whole
    /// document wins and later edits apply onto it).
    public static func compose(_ edits: [TargetsEdit], onto hub: TargetsDocument?) -> TargetsDocument? {
        var current = hub
        for e in edits {
            if e.base == nil { current = e.document; continue }
            guard let c = current else { return nil }
            current = e.applied(to: c)
        }
        return current
    }

    /// True when sending needs the hub's current document first (the oldest edit is a patch).
    public static func needsHubCopy(_ edits: [TargetsEdit]) -> Bool { edits.first.map { $0.base != nil } ?? false }
}

extension TargetsDocument {
    /// `hub` with every target this document changed relative to `base` (and nothing else).
    public func rebased(onto hub: TargetsDocument, from base: TargetsDocument) -> TargetsDocument {
        var out = hub
        func take<T: Equatable>(_ kp: WritableKeyPath<TargetsDocument, T>) {
            if self[keyPath: kp] != base[keyPath: kp] { out[keyPath: kp] = self[keyPath: kp] }
        }
        take(\.goals.weight); take(\.goals.kcal); take(\.goals.proteinG); take(\.goals.carbsG)
        take(\.goals.fatG); take(\.goals.stepsDaily); take(\.goals.sleepH); take(\.goals.strength)
        take(\.limits.hrCapBpm); take(\.limits.hrCapConfirmedOn); take(\.limits.zones); take(\.limits.avoidZone5)
        for r in RuleMetric.allCases where rules[r] != base.rules[r] { out.rules[r] = rules[r] }
        out.clearAllGoals = clearAllGoals && out.goals.isEmpty
        return out
    }
}
