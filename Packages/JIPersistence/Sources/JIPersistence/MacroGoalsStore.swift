import Foundation
import JICore

/// B-73: JI owns the nutrition goals, and the phone is their source of truth. They are stored
/// under `goals.macros`. Nothing is seeded: with no row, `load()` returns `.unset` (every surface
/// then shows "Set your goal") and writes nothing. Personal nutrition parameters are user input,
/// never app-imposed numbers (Toby 2026-09-24). A row that exists but does not decode throws. It
/// is never silently reset, because that would drop the user's goals (rule 5: never invent).
public struct MacroGoalsStore: Sendable {
    public static let key = "goals.macros"
    private let prefs: PrefStore

    public init(prefs: PrefStore) { self.prefs = prefs }

    public func load() throws -> MacroGoals {
        try prefs.get(Self.key, as: MacroGoals.self) ?? .unset
    }

    public func save(_ goals: MacroGoals) throws { try prefs.set(Self.key, goals) }
}
