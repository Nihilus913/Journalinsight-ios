import Foundation

public struct TodayActivity: Codable, Sendable, Equatable {
    public var name, type: String?
    public var durationSec, avgHr, maxHr: Int?
    public var teAerobic: Double?
}
public struct Experiment: Codable, Sendable, Equatable {
    public var count, target: Int
    public var executionScore: Double?
    public var wantsCompletePrompt: Bool?
}
public struct HrvPoint: Codable, Sendable, Equatable {
    public var date: String
    public var hrvWeeklyAvg, rhrBpm: Double?
}
public struct MorningResponse: Codable, Sendable, Equatable {
    public var todayActivities: [TodayActivity]
    public var verdict, verdictDate: String?
    public var experiment: Experiment?
    public var carbs3dAvg: Double?
    public var carbWatchFloor: Double
    public var hrvSeries: [HrvPoint]
    /// B-45 / W-B46 Contract (L3 adds these to `GET /api/v1/planning/morning`). OPTIONAL on
    /// purpose: `verdict`/`verdict_date` come from a JSONL log that `scripts/morning_go.py`
    /// writes, so a day the script did not run serves yesterday's verdict verbatim. `isStale`
    /// says so, and `sessionForToday` is the session the hub derives from `plan_session.weekday`
    /// for the REAL day instead. A hub that predates the route still decodes (both nil).
    public var isStale: Bool?
    public var sessionForToday: String?
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
