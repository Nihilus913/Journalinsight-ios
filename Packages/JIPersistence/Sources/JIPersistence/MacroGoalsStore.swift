import Foundation
import JICore

/// B-73: JI owns the nutrition goals, and the phone is their source of truth. They are stored
/// under `goals.macros`. Nothing is seeded: with no row, `load()` returns `.unset` (every surface
/// then shows "Set your goal") and writes nothing. Personal nutrition parameters are user input,
/// never app-imposed numbers (Toby 2026-09-24). A row that exists but does not decode throws. It
/// is never silently reset, because that would drop the user's goals (rule 5: never invent).
///
/// W-TGT: once the targets document exists (`TargetsStore`, after the §5 import), this store reads
/// and writes its Goals (kcal + basis, P/C/F) — one number per metric, no second copy. Before the
/// import it keeps the `goals.macros` row, which the import then carries over verbatim.
public struct MacroGoalsStore: Sendable {
    public static let key = "goals.macros"
    private let prefs: PrefStore

    public init(prefs: PrefStore) { self.prefs = prefs }

    public func load() throws -> MacroGoals {
        if let doc = try TargetsStore(prefs: prefs).loadThrowing() { return doc.macroGoals }
        return try prefs.get(Self.key, as: MacroGoals.self) ?? .unset
    }

    public func save(_ goals: MacroGoals) throws {
        let targets = TargetsStore(prefs: prefs)
        guard var doc = try targets.loadThrowing() else { return try prefs.set(Self.key, goals) }
        doc.macroGoals = goals
        try targets.save(doc)
    }
}
