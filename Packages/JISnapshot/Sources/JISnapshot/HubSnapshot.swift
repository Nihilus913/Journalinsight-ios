import Foundation
import JICore

/// A compact "My KPIs" entry: label, optional value, optional unit.
/// A fresh Codable+Sendable projection rather than a reuse of JICore's
/// `DailyKpiRow` — that type shapes a date + a values dictionary, not a
/// single labeled metric, so it doesn't fit the widget's row shape.
public struct SnapshotKPI: Codable, Equatable, Sendable {
    /// W-B34 (B-36): stable KPI identity so a configured widget can find "the KPI the user picked"
    /// without matching on label text. Optional so snapshots stored before W-B34 still decode;
    /// Today's chip projection (`kpis`) may leave it nil.
    public var id: KpiMetricId?
    public var label: String
    public var value: Double?
    public var unit: String?

    public init(id: KpiMetricId? = nil, label: String, value: Double?, unit: String?) {
        self.id = id
        self.label = label
        self.value = value
        self.unit = unit
    }
}

/// Widget/complication-facing snapshot of the Home hub's latest morning
/// state. Foundation-only, Codable+Equatable+Sendable so it can round-trip
/// through App-Group `UserDefaults` (see `SnapshotStore`).
///
/// Deliberately excludes the connection token or any other secret — the
/// widget process must never be able to read the hub credential.
public struct HubSnapshot: Codable, Equatable, Sendable {
    /// Projection of JICore's `VerdictParts.word` (e.g. "GO", "REDUCED (session)", "—").
    public var verdictWord: String
    /// Projection of JICore's `VerdictParts.session`.
    public var verdictSession: String
    /// Projection of JICore's `VerdictTone`: "go" / "amber" / "red" / "muted".
    public var verdictTone: String
    /// Projection of JICore's `MorningResponse.verdictDate` (raw wire string, e.g. "2026-09-13").
    public var verdictDate: String?

    /// Latest recovery day's readiness score, 0-100. `nil` when not yet available.
    public var readiness: Double?

    /// Top-N "My KPIs" for the widget face.
    public var kpis: [SnapshotKPI]

    /// W-B34 (B-36): one entry per `KpiMetricId.allCases` (latest non-nil value, or nil) for the
    /// configurable KPI widget. Optional so snapshots stored before W-B34 still decode (nil).
    public var allKpis: [SnapshotKPI]?

    /// When this snapshot was produced by the app/extension.
    public var fetchedAt: Date
    /// Last known hub sync time, if any.
    public var lastSync: Date?

    /// B-57 W2 (B-73): macros left to the user's own JI goals. Optional, so older snapshots decode (nil).
    public var macros: SnapshotMacros?

    public init(
        verdictWord: String,
        verdictSession: String,
        verdictTone: String,
        verdictDate: String?,
        readiness: Double?,
        kpis: [SnapshotKPI],
        allKpis: [SnapshotKPI]? = nil,
        fetchedAt: Date,
        lastSync: Date?,
        macros: SnapshotMacros? = nil
    ) {
        self.verdictWord = verdictWord
        self.verdictSession = verdictSession
        self.verdictTone = verdictTone
        self.verdictDate = verdictDate
        self.readiness = readiness
        self.kpis = kpis
        self.allKpis = allKpis
        self.fetchedAt = fetchedAt
        self.lastSync = lastSync
        self.macros = macros
    }

    /// W-B34 (B-36): the snapshot entry for one KPI — `allKpis` first, then Today's `kpis`, matched
    /// by `id` (never by label). nil when neither carries it (e.g. a pre-W-B34 snapshot).
    public func kpi(_ id: KpiMetricId) -> SnapshotKPI? {
        allKpis?.first { $0.id == id } ?? kpis.first { $0.id == id }
    }
}

/// B-57 W2 (B-73): one macro's goal and what is left of it today (never negative).
public struct SnapshotMacro: Codable, Equatable, Sendable {
    public var goal: Double
    public var left: Double
    public init(goal: Double, left: Double) { self.goal = goal; self.left = left }
}

/// B-73: "Left to your goals" for KpiWidget medium/inline. The goals are the user's own
/// (`MacroGoals`; kcal = the user's target); "eaten" is today's Health dietary total. A goal the
/// user has not set is nil here and omitted, never a number.
public struct SnapshotMacros: Codable, Equatable, Sendable {
    public var kcal, protein, carbs, fat: SnapshotMacro?
    public var asOf: Date?

    public init(kcal: SnapshotMacro?, protein: SnapshotMacro?, carbs: SnapshotMacro?, fat: SnapshotMacro?, asOf: Date?) {
        self.kcal = kcal; self.protein = protein; self.carbs = carbs; self.fat = fat; self.asOf = asOf
    }

    /// nil when Health food is not readable (never granted / nothing in the window) or no goal
    /// exists: rule 5, the widget then shows its KPI face instead of a made-up "left".
    public static func make(
        goals: (kcal: Double?, protein: Double?, carbs: Double?, fat: Double?),
        eatenToday: (kcal: Double?, protein: Double?, carbs: Double?, fat: Double?),
        healthReadable: Bool, asOf: Date?
    ) -> SnapshotMacros? {
        guard healthReadable else { return nil }
        func one(_ goal: Double?, _ eaten: Double?) -> SnapshotMacro? {
            guard let goal, goal.isFinite, goal > 0 else { return nil }
            return SnapshotMacro(goal: goal, left: max(0, goal - (eaten ?? 0)))
        }
        let m = SnapshotMacros(kcal: one(goals.kcal, eatenToday.kcal), protein: one(goals.protein, eatenToday.protein),
                               carbs: one(goals.carbs, eatenToday.carbs), fat: one(goals.fat, eatenToday.fat), asOf: asOf)
        return [m.kcal, m.protein, m.carbs, m.fat].allSatisfy { $0 == nil } ? nil : m
    }

    /// Board 6/09 KpiWidgetInline: "Protein 103 g to goal", "1150 kcal to goal", "Carbs goal met";
    /// nil for a non-macro KPI or an unset goal (the face then falls back to its KPI text).
    public func inlineText(for id: KpiMetricId) -> String? {
        let (macro, name, unit): (SnapshotMacro?, String, String)
        switch id {
        case .kcal: (macro, name, unit) = (kcal, "kcal", "kcal")
        case .protein: (macro, name, unit) = (protein, "Protein", "g")
        case .carbs: (macro, name, unit) = (carbs, "Carbs", "g")
        case .fat: (macro, name, unit) = (fat, "Fat", "g")
        default: return nil
        }
        guard let macro else { return nil }
        let left = Int(macro.left.rounded())
        if left == 0 { return "\(name) goal met" }
        return id == .kcal ? "\(left) kcal to goal" : "\(name) \(left) \(unit) to goal"
    }
}
