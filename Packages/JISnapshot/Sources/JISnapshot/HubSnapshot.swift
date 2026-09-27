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
    /// B-57 W5: the 28-day personal normal (W3 `PersonalNormal`) for the KpiWidget small band.
    /// Optional, so snapshots written before W5 decode (nil = no band, "Calibrating").
    public var normalLow: Double?
    public var normalHigh: Double?

    public init(id: KpiMetricId? = nil, label: String, value: Double?, unit: String?, normalLow: Double? = nil, normalHigh: Double? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.unit = unit
        self.normalLow = normalLow
        self.normalHigh = normalHigh
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

    /// B-57 W5: one line (≤ 48 chars) from the gate's first red, else first amber signal. nil = nothing held the call back.
    public var reason: String?
    /// B-57 W5: strength sessions done this week / in the plan (the "2 of 4" ring). nil = unknown.
    public var planDone: Int?
    public var planTotal: Int?
    /// B-57 W5: the user's HR cap (W4 setting) as stored. nil = no cap (Toby 2026-09-24: optional,
    /// never a fallback) — the glances then show the next session in the cap's slot.
    public var hrCap: Int?
    /// B-57 W5: "Fri · Day 3 Full Upper" — the next strength session not yet done this week.
    public var nextSession: String?
    /// B-57 W5: HRV / Sleep / Resting HR against normal or goal, for GateWidget medium, the Watch and the Live Activity.
    public var signals: [SnapshotSignal]?

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
        macros: SnapshotMacros? = nil,
        reason: String? = nil,
        planDone: Int? = nil,
        planTotal: Int? = nil,
        hrCap: Int? = nil,
        nextSession: String? = nil,
        signals: [SnapshotSignal]? = nil
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
        self.reason = reason.flatMap(HubSnapshot.clipReason)
        self.planDone = planDone
        self.planTotal = planTotal
        self.hrCap = hrCap
        self.nextSession = nextSession
        self.signals = signals
    }

    private enum CodingKeys: String, CodingKey {
        case verdictWord, verdictSession, verdictTone, verdictDate, readiness, kpis, allKpis, fetchedAt, lastSync, macros
        case reason, planDone, planTotal, hrCap, nextSession, signals
    }

    /// B-57 W5: every field added after W2c decodes with `decodeIfPresent`, and the W2/W5 extras
    /// through `try?` as well — a malformed extra must never cost the widget its verdict
    /// (`SnapshotStore.read()` turns any throw into "No data yet").
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        verdictWord = try c.decode(String.self, forKey: .verdictWord)
        verdictSession = try c.decode(String.self, forKey: .verdictSession)
        verdictTone = try c.decode(String.self, forKey: .verdictTone)
        verdictDate = try c.decodeIfPresent(String.self, forKey: .verdictDate)
        readiness = try c.decodeIfPresent(Double.self, forKey: .readiness)
        kpis = try c.decode([SnapshotKPI].self, forKey: .kpis)
        allKpis = try c.decodeIfPresent([SnapshotKPI].self, forKey: .allKpis)
        fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)
        lastSync = try c.decodeIfPresent(Date.self, forKey: .lastSync)
        macros = (try? c.decodeIfPresent(SnapshotMacros.self, forKey: .macros)) ?? nil
        reason = ((try? c.decodeIfPresent(String.self, forKey: .reason)) ?? nil).flatMap(HubSnapshot.clipReason)
        planDone = (try? c.decodeIfPresent(Int.self, forKey: .planDone)) ?? nil
        planTotal = (try? c.decodeIfPresent(Int.self, forKey: .planTotal)) ?? nil
        hrCap = (try? c.decodeIfPresent(Int.self, forKey: .hrCap)) ?? nil      // missing/malformed = no cap shown
        nextSession = (try? c.decodeIfPresent(String.self, forKey: .nextSession)) ?? nil
        signals = (try? c.decodeIfPresent([SnapshotSignal].self, forKey: .signals)) ?? nil
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
