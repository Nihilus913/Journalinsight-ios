import Foundation

/// W-B101 (Bevel BP-21, slice S1): the rule-based plan builder's draft + validator, hub-less.
/// Twin of HT `app/planning/plan_draft.py`; both pass HT `tests/fixtures/plan_draft/plan_draft.golden.json`
/// (byte copy in `JIComputeTests/Resources/plan_draft/`). Toby 2026-10-04: NO LLM — every draft is
/// deterministic and must pass these five checks before it is shown or saved:
///
///   hrCap         every hr target hi <= the user's cap (no cap -> skip)
///   zone5         avoid-Zone-5 on: no target hi >= the Z5 floor (off / no floors -> skip)
///   hardSessions  sessions of kind interval or with a target lo >= the Z4 floor <= max per week
///   restDay       >= 1 rest day per week (no sessions, or only rest sessions)
///   loadRamp      weekly minutes <= +maxRampPct % on the week before (week 1 vs the baseline);
///                 ACWR above the hold line: week 1 must not exceed the baseline -> held, above -> fail
///
/// `value`: hrCap / zone5 = highest target hi; hardSessions = max per week; restDay = min per week;
/// loadRamp = first failing week (1-based) or nil. Integer ramp arithmetic, bit-exact with Python.
public nonisolated struct PlanHrTarget: Sendable, Equatable, Codable {
    public let lo: Int
    public let hi: Int
    public init(lo: Int, hi: Int) { self.lo = lo; self.hi = hi }
}

public nonisolated enum PlanSessionKind: String, Sendable, Equatable, Codable, CaseIterable {
    case strength, interval, zone2, rest
}

public nonisolated struct PlanDraftSession: Sendable, Equatable, Codable {
    public let kind: PlanSessionKind
    public let minutes: Int
    public let targets: [PlanHrTarget]
    public init(kind: PlanSessionKind, minutes: Int, targets: [PlanHrTarget] = []) {
        self.kind = kind; self.minutes = minutes; self.targets = targets
    }
}

public nonisolated struct PlanDraftDay: Sendable, Equatable, Codable {
    /// 0 = Monday.
    public let weekday: Int
    public let sessions: [PlanDraftSession]
    public init(weekday: Int, sessions: [PlanDraftSession]) { self.weekday = weekday; self.sessions = sessions }
}

public nonisolated struct PlanDraftWeek: Sendable, Equatable, Codable {
    public let days: [PlanDraftDay]
    public init(days: [PlanDraftDay]) { self.days = days }
}

public nonisolated struct PlanDraft: Sendable, Equatable, Codable {
    public let weeks: [PlanDraftWeek]
    public let baselineMinutes: Int?
    public init(weeks: [PlanDraftWeek], baselineMinutes: Int? = nil) { self.weeks = weeks; self.baselineMinutes = baselineMinutes }
    enum CodingKeys: String, CodingKey { case weeks, baselineMinutes = "baseline_minutes" }
}

public nonisolated struct PlanRules: Sendable, Equatable, Codable {
    public let hrCap: Int?
    public let avoidZone5: Bool
    public let zoneFloors: [Int]?
    public let maxHardPerWeek: Int
    public let maxRampPct: Int
    public let acwr: Double?
    public let acwrHoldAbove: Double
    public init(hrCap: Int?, avoidZone5: Bool, zoneFloors: [Int]?, maxHardPerWeek: Int = 2, maxRampPct: Int = 10,
                acwr: Double? = nil, acwrHoldAbove: Double = 1.3) {
        self.hrCap = hrCap; self.avoidZone5 = avoidZone5; self.zoneFloors = zoneFloors
        self.maxHardPerWeek = maxHardPerWeek; self.maxRampPct = maxRampPct; self.acwr = acwr; self.acwrHoldAbove = acwrHoldAbove
    }
    enum CodingKeys: String, CodingKey {
        case hrCap = "hr_cap", avoidZone5 = "avoid_zone5", zoneFloors = "zone_floors", maxHardPerWeek = "max_hard_per_week"
        case maxRampPct = "max_ramp_pct", acwr, acwrHoldAbove = "acwr_hold_above"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hrCap = try c.decodeIfPresent(Int.self, forKey: .hrCap)
        avoidZone5 = try c.decodeIfPresent(Bool.self, forKey: .avoidZone5) ?? false
        let floors = try c.decodeIfPresent([Int].self, forKey: .zoneFloors)
        zoneFloors = (floors?.isEmpty ?? true) ? nil : floors
        maxHardPerWeek = try c.decodeIfPresent(Int.self, forKey: .maxHardPerWeek) ?? 2
        maxRampPct = try c.decodeIfPresent(Int.self, forKey: .maxRampPct) ?? 10
        acwr = try c.decodeIfPresent(Double.self, forKey: .acwr)
        acwrHoldAbove = try c.decodeIfPresent(Double.self, forKey: .acwrHoldAbove) ?? 1.3
    }
}

public nonisolated enum PlanCheckID: String, Sendable, Equatable, CaseIterable {
    case hrCap = "hr_cap", zone5, hardSessions = "hard_sessions", restDay = "rest_day", loadRamp = "load_ramp"
}

public nonisolated enum PlanCheckStatus: String, Sendable, Equatable {
    case pass, fail, held, skip
}

public nonisolated struct PlanCheck: Sendable, Equatable {
    public let id: PlanCheckID
    public let status: PlanCheckStatus
    public let value: Int?
    public let detail: String
}

public nonisolated func validatePlanDraft(_ draft: PlanDraft, rules: PlanRules) -> [PlanCheck] {
    let sessions = draft.weeks.flatMap { $0.days.flatMap(\.sessions) }
    let top = sessions.flatMap(\.targets).map(\.hi).max()
    var out: [PlanCheck] = []

    if let cap = rules.hrCap {
        if let top, top > cap {
            out.append(PlanCheck(id: .hrCap, status: .fail, value: top, detail: "A target reaches \(top) bpm, above your \(cap) bpm cap"))
        } else {
            let shown = top.map { "highest target \($0) bpm" } ?? "no HR targets"
            out.append(PlanCheck(id: .hrCap, status: .pass, value: top, detail: "Cap \(cap) bpm · \(shown)"))
        }
    } else {
        out.append(PlanCheck(id: .hrCap, status: .skip, value: top, detail: "No HR cap set"))
    }

    if rules.avoidZone5, let floors = rules.zoneFloors, floors.count == 5 {
        let z5 = floors[4]
        if let top, top >= z5 {
            out.append(PlanCheck(id: .zone5, status: .fail, value: top, detail: "A target reaches \(top) bpm, into Zone 5 (from \(z5))"))
        } else {
            out.append(PlanCheck(id: .zone5, status: .pass, value: top, detail: "No target at or above \(z5) bpm"))
        }
    } else {
        out.append(PlanCheck(id: .zone5, status: .skip, value: top, detail: rules.avoidZone5 ? "No zones set" : "Zone 5 is allowed"))
    }

    let z4 = (rules.zoneFloors?.count == 5) ? rules.zoneFloors?[3] : nil
    func isHard(_ s: PlanDraftSession) -> Bool {
        s.kind == .interval || (z4.map { f in s.targets.contains { $0.lo >= f } } ?? false)
    }
    let perWeek = draft.weeks.map { w in w.days.flatMap(\.sessions).filter(isHard).count }
    let most = perWeek.max() ?? 0
    let list = perWeek.isEmpty ? "0" : perWeek.map(String.init).joined(separator: " · ")
    out.append(PlanCheck(id: .hardSessions, status: most > rules.maxHardPerWeek ? .fail : .pass, value: most,
                         detail: "Hard sessions a week: \(list) (max \(rules.maxHardPerWeek))"))

    let rests = draft.weeks.map { w in
        7 - Set(w.days.filter { d in d.sessions.contains { $0.kind != .rest } }.map(\.weekday)).count
    }
    let least = rests.min() ?? 7
    out.append(PlanCheck(id: .restDay, status: least < 1 ? .fail : .pass, value: least,
                         detail: least < 1 ? "A week has no rest day" : "At least one rest day every week"))

    let mins = draft.weeks.map { $0.days.flatMap(\.sessions).reduce(0) { $0 + $1.minutes } }
    let prev: [Int?] = [draft.baselineMinutes] + mins.dropLast().map { Optional($0) }
    let pct = rules.maxRampPct
    let hold = rules.acwr.map { $0 > rules.acwrHoldAbove } ?? false
    var firstFail: Int?
    var compared = 0
    for (i, m) in mins.enumerated() {
        guard let p = prev[i] else { continue }
        compared += 1
        let hit = (i == 0 && hold) ? (m > p) : (m * 100 > p * (100 + pct))
        if hit { firstFail = i + 1; break }
    }
    let ratio = rules.acwr.map { String(format: "%.2f", $0) } ?? ""
    if let w = firstFail {
        let why = (hold && w == 1) ? " (load ratio \(ratio): week 1 must hold)" : ""
        out.append(PlanCheck(id: .loadRamp, status: .fail, value: w, detail: "Week \(w) raises the weekly load by more than allowed\(why)"))
    } else if compared == 0 {
        out.append(PlanCheck(id: .loadRamp, status: .skip, value: nil, detail: "No earlier week to compare with"))
    } else if hold {
        out.append(PlanCheck(id: .loadRamp, status: .held, value: nil,
                             detail: "Your load ratio is \(ratio) (above \(rules.acwrHoldAbove)): week 1 holds this week's load"))
    } else {
        out.append(PlanCheck(id: .loadRamp, status: .pass, value: nil, detail: "Weekly load rises at most \(pct) % a week"))
    }
    return out
}
