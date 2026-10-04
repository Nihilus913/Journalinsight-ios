import Foundation

/// W-PLANNER PL-3 — `GET /api/v1/planning/workouts` (HT PL-1): the active plan's strength + cardio
/// sessions ∪ the workout templates as ONE read list — the Planner's "All workouts". Read-only;
/// the writes stay where they are (a session's weekday: `PUT /planning/plan-sessions/{id}`; a
/// template's `weekdays`: its own template PUT). Snake_case keys via `JSON.decoder`.
public struct PlannerWorkout: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case planSession = "plan_session", template
        /// A kind a newer hub sends that this build does not know — shown, never acted on.
        case other

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .other
        }
    }

    /// `"s<plan_session id>"` | `"t<template id>"` — unique across the list.
    public var ref: String
    public var kind: Kind
    public var name: String
    /// `"strength"` | `"running"` | … (the template's sport; a cardio session is `"running"`).
    public var sport: String
    /// Mon = 0 … Sun = 6; `[]` = not on a day.
    public var weekdays: [Int]
    public var liftCount: Int
    /// The hub's one-line summary ("6 lifts", "40 min"); nil = the phone words it.
    public var summary: String?
    /// The template's Garmin Connect counterpart (nil = none, or the hub sent only a flag).
    public var garmin: GarminLink?
    /// true when the hub said the row is on Garmin Connect (object or `true`).
    public var onGarmin: Bool
    /// true = opens the workout editor (a template); false = a plan session (strength detail).
    public var editable: Bool
    /// PL-8 (HT migration 060): on a template, the plan sessions linked to it by id (`"s<id>"`) —
    /// such a session IS this template (its weekday shows here; the hub does not list it alone).
    /// `[]` on sessions, unlinked templates and older hubs. Never inferred from names.
    public var linkedRefs: [String]

    public var id: String { ref }

    public init(ref: String, kind: Kind, name: String, sport: String, weekdays: [Int], liftCount: Int = 0,
                summary: String? = nil, garmin: GarminLink? = nil, onGarmin: Bool? = nil, editable: Bool, linkedRefs: [String] = []) {
        self.ref = ref; self.kind = kind; self.name = name; self.sport = sport; self.weekdays = weekdays
        self.liftCount = liftCount; self.summary = summary; self.garmin = garmin
        self.onGarmin = onGarmin ?? (garmin != nil); self.editable = editable; self.linkedRefs = linkedRefs
    }

    private enum CodingKeys: String, CodingKey { case ref, kind, name, sport, weekdays, liftCount, summary, garmin, editable, linkedRefs }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ref = try c.decode(String.self, forKey: .ref)
        kind = try c.decode(Kind.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        sport = try c.decodeIfPresent(String.self, forKey: .sport) ?? "running"
        weekdays = try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
        liftCount = try c.decodeIfPresent(Int.self, forKey: .liftCount) ?? 0
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        editable = try c.decodeIfPresent(Bool.self, forKey: .editable) ?? false
        linkedRefs = (try? c.decodeIfPresent([String].self, forKey: .linkedRefs)) ?? []
        if let link = try? c.decodeIfPresent(GarminLink.self, forKey: .garmin) {
            garmin = link; onGarmin = true
        } else {
            garmin = nil
            onGarmin = (try? c.decodeIfPresent(Bool.self, forKey: .garmin)) ?? false
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ref, forKey: .ref)
        try c.encode(kind == .other ? "other" : kind.rawValue, forKey: .kind)
        try c.encode(name, forKey: .name)
        try c.encode(sport, forKey: .sport)
        try c.encode(weekdays, forKey: .weekdays)
        try c.encode(liftCount, forKey: .liftCount)
        try c.encodeIfPresent(summary, forKey: .summary)
        if let garmin { try c.encode(garmin, forKey: .garmin) } else { try c.encode(onGarmin, forKey: .garmin) }
        try c.encode(editable, forKey: .editable)
        try c.encode(linkedRefs, forKey: .linkedRefs)
    }

    /// The `plan_session` id (`"s12"` → 12), nil for a template.
    public var sessionId: Int? { kind == .planSession && ref.hasPrefix("s") ? Int(ref.dropFirst()) : nil }
    /// The `workout_template` id (`"t3"` → 3), nil for a session.
    public var templateId: Int? { kind == .template && ref.hasPrefix("t") ? Int(ref.dropFirst()) : nil }
    public var isStrength: Bool { sport.lowercased() == "strength" }
    /// The linked plan-session ids (`"s5"` → 5).
    public var linkedSessionIds: [Int] { linkedRefs.compactMap { $0.hasPrefix("s") ? Int($0.dropFirst()) : nil } }
}

/// PL-8: plan-session id → the template it is linked to, from the hub's rows (`linked_refs`).
/// Empty for an older hub (no links) — the phone then shows both, never guesses by name.
public nonisolated func plannerSessionTemplateLinks(_ rows: [PlannerWorkout]) -> [Int: Int] {
    var out: [Int: Int] = [:]
    for row in rows { if let tid = row.templateId { for sid in row.linkedSessionIds where out[sid] == nil { out[sid] = tid } } }
    return out
}

/// PL-3: the Planner's read slice (one protocol per screen's hub routes). Defaulted: a provider
/// without the route throws `PlannerWorkoutsUnavailable` and the phone builds the same list from
/// what it already caches (`plannerWorkoutsFallback`).
public protocol PlannerProviding: Sendable {
    /// `GET /api/v1/planning/workouts`
    func plannerWorkouts() async throws -> [PlannerWorkout]
}

public extension PlannerProviding {
    func plannerWorkouts() async throws -> [PlannerWorkout] { throw PlannerWorkoutsUnavailable() }
}

/// The hub has no `/planning/workouts` (404) — an older hub.
public struct PlannerWorkoutsUnavailable: Error, Sendable, Equatable {
    public init() {}
}

/// PL-3 fallback (old hub): the same list from the cached rows — the plan's sessions in plan
/// order (Rest excluded; a strength session only the exercise rows know is added after), then
/// the template library. Lift counts come from the exercise rows; summaries are left to the phone.
public nonisolated func plannerWorkoutsFallback(exercises: [Exercise], planSessions: [PlanSessionOut], templates: [WorkoutTemplate]) -> [PlannerWorkout] {
    func lifts(id: Int?, name: String) -> Int {
        let byId = id.map { sid in exercises.filter { $0.sessionId == sid } } ?? []
        return byId.isEmpty ? exercises.filter { $0.sessionName == name }.count : byId.count
    }
    var out: [PlannerWorkout] = []
    var seenIds = Set<Int>(), seenNames = Set<String>()
    for s in planSessions {
        let type = s.sessionType?.lowercased()
        guard type != "rest", !seenIds.contains(s.id) else { continue }
        seenIds.insert(s.id); seenNames.insert(s.name)
        let n = lifts(id: s.id, name: s.name)
        let strength = type == "strength" || (type == nil && n > 0)
        out.append(PlannerWorkout(ref: "s\(s.id)", kind: .planSession, name: s.name, sport: strength ? "strength" : "running",
                                  weekdays: s.weekday.map { [$0] } ?? [], liftCount: n, editable: false))
    }
    for e in exercises where !seenNames.contains(e.sessionName) && !(e.sessionId.map(seenIds.contains) ?? false) {
        seenNames.insert(e.sessionName)
        let id = e.sessionId
        if let id { seenIds.insert(id) }
        let wd = exercises.first { $0.sessionName == e.sessionName && $0.weekday != nil }?.weekday
        out.append(PlannerWorkout(ref: id.map { "s\($0)" } ?? "s:\(e.sessionName)", kind: .planSession, name: e.sessionName,
                                  sport: "strength", weekdays: wd.map { [$0] } ?? [], liftCount: lifts(id: id, name: e.sessionName),
                                  editable: false))
    }
    for t in templates {
        out.append(PlannerWorkout(ref: "t\(t.templateId)", kind: .template, name: t.name, sport: t.hasStrength ? "strength" : t.activity,
                                  weekdays: Array(Set(t.weekdays)).sorted(), garmin: t.garmin, editable: true))
    }
    return out
}
