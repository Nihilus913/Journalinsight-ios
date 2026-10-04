import Foundation

public struct MorningResponse: Codable, Sendable, Equatable {
    public var verdict, verdictDate: String?
    public var carbs3dAvg: Double?
    public var carbWatchFloor: Double
    /// B-45 / W-B46 Contract (L3 adds these to `GET /api/v1/planning/morning`). OPTIONAL on
    /// purpose: `verdict`/`verdict_date` come from a JSONL log that `scripts/morning_go.py`
    /// writes, so a day the script did not run serves yesterday's verdict verbatim. `isStale`
    /// says so, and `sessionForToday` is the session the hub derives from `plan_session.weekday`
    /// for the REAL day instead. A hub that predates the route still decodes (both nil).
    public var isStale: Bool?
    public var sessionForToday: String?
    /// W-B57b (B-61) — the four `morning_go.evaluate` inputs behind `verdict` (sleep, HRV, RHR,
    /// sleep time), as stored with the verdict for `verdictDate`. OPTIONAL: nil from a hub that
    /// predates the field or for a verdict row written before migration 048.
    public var gateSignals: [GateSignal]?
    /// W-B57b (B-62) — the user's override of the verdict for `verdictDate`, nil when none.
    public var verdictOverride: VerdictOverride?
    /// W-B49B G-3 — today's session-gate answer (automatic or manual); nil = unanswered or a hub
    /// that predates the field.
    public var gateAnswer: GateAnswer?
    /// W-DECIDE-HYBRID H-2 — when the hub made the call (`plan.morning_verdict.computed_at`, ISO
    /// 8601): Decide's "YOUR CALL FOR TODAY · 05:10" and "values at 05:10". nil from an older hub.
    public var verdictComputedAt: String?
    /// W-DECIDE-HYBRID H-3/H-4 — the Strain card's numbers (HT `app/vitals/strain.py`). nil from an
    /// older hub or when the hub could not read the load. The card's "max today" is NOT here: it
    /// follows the decided call (`DecideStrainCeiling`).
    public var strain: MorningStrain?

    // B-48: `JSON.decoder` sets `.keyDecodingStrategy = .convertFromSnakeCase`, which rewrites the
    // wire key BEFORE `CodingKeys` matching — and a snake_case segment that STARTS with a digit
    // gets its first letter upper-cased on the join (`carbs_3d_avg` -> `carbs3DAvg`). An explicit raw
    // value must therefore be the MANGLED spelling, never the wire string (verified against a real
    // `Foundation.JSONDecoder`; `DailyKpiRow`'s custom `init(from:)` below is the existing idiom).
    // Adding one case obliges us to list every stored property, so the rest are bare cases whose
    // default raw value already equals what the strategy produces.
    enum CodingKeys: String, CodingKey {
        case verdict, verdictDate
        case carbs3dAvg = "carbs3DAvg"
        case carbWatchFloor, isStale, sessionForToday
        case gateSignals, verdictOverride, gateAnswer
        case verdictComputedAt, strain
    }
}

/// W-DECIDE-HYBRID: daily Strain 0–100 (HT `app/vitals/strain.py`): yesterday's and today-so-far
/// strain against the usual range (middle 50 % of loaded days over `windowDays`). While
/// `status == "calibrating"` every number is nil (fewer than `minLoadedDays` loaded days).
public struct MorningStrain: Codable, Sendable, Equatable {
    public struct Day: Codable, Sendable, Equatable {
        public var date: String
        public var value: Double?
        public var sessions: [Session]?
        public init(date: String, value: Double?, sessions: [Session]? = nil) {
            self.date = date; self.value = value; self.sessions = sessions
        }
    }
    public struct Session: Codable, Sendable, Equatable {
        public var name: String
        public var minutes: Int
        public init(name: String, minutes: Int) { self.name = name; self.minutes = minutes }
    }
    public var status: String
    public var loadedDays: Int
    public var minLoadedDays: Int
    public var windowDays: Int
    public var ceiling: Double?
    public var usualLow: Double?
    public var usualHigh: Double?
    public var yesterday: Day
    public var today: Day

    public init(status: String, loadedDays: Int, minLoadedDays: Int = 19, windowDays: Int = 120, ceiling: Double? = nil,
                usualLow: Double?, usualHigh: Double?, yesterday: Day, today: Day) {
        self.status = status; self.loadedDays = loadedDays; self.minLoadedDays = minLoadedDays; self.windowDays = windowDays
        self.ceiling = ceiling; self.usualLow = usualLow; self.usualHigh = usualHigh; self.yesterday = yesterday; self.today = today
    }

    public var isCalibrating: Bool { status != "ok" }
}
public struct MorningVerdict: Codable, Sendable, Equatable {
    public var date, verdict: String
    public var reason, sessionPrescription: String?
    public var computedAt: String
}

public enum VerdictTone: Sendable, Equatable { case go, amber, red, muted }
public struct VerdictParts: Sendable, Equatable { public var word, session: String; public var tone: VerdictTone }

/// Port of mobile/src/lib/verdict.ts — `word` keeps the parenthetical (as RN does), tone strips it.
public func verdictParts(_ v: String?) -> VerdictParts {
    guard let v, !v.isEmpty else { return VerdictParts(word: "—", session: "No verdict yet", tone: .muted) }
    let pieces = v.split(separator: "—", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
    let head = pieces.first ?? ""
    let session = pieces.count > 1 ? pieces[1] : ""
    let bare = head.replacing(/\(.*\)/, with: "").trimmingCharacters(in: .whitespaces)
    // Deliberate deviation from mobile/src/lib/verdict.ts, whose startsWith("RED") also catches
    // "REDUCED" — the design reserves amber for REDUCED (mobile/src/theme/tokens.ts
    // verdict.reduced + plan L24, 2026-09-13 ruling).
    let tone: VerdictTone = bare.hasPrefix("GO") ? .go : bare.hasPrefix("REDUCED") ? .amber : bare.hasPrefix("RED") ? .red : .amber
    return VerdictParts(word: head, session: session, tone: tone)
}
