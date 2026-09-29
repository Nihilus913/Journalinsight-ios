import Foundation

/// W5b-L4 (P-gate-respond) — the two planning writes Today never got in Swift:
/// `POST /api/v1/planning/gate/respond` (HT `app/planning/router.py:325`, `GateRespondBody` →
/// `GateRespondOut`) and `POST /api/v1/planning/feel` (`:360`, `FeelBody` → `FeelOut`).
///
/// Both bodies carry explicit snake_case `CodingKeys`: `HubClient.send` encodes with a plain
/// `JSONEncoder()` (never `JSON.encoder`), so the wire shape has to be spelled out here — and
/// `Outbox.enqueue`/a drainer use a plain `JSONEncoder`/`JSONDecoder` pair too, so the same
/// explicit keys round-trip through the durable queue unchanged. Responses decode through
/// `JSON.decoder` (`.convertFromSnakeCase`), so the *Out* types stay camelCase.

/// Mirrors HT `GateRespondBody.choice`'s `Literal["y", "N", "override"]` exactly — and the RN
/// oracle's `GateChoice` (`mobile/src/data/types.ts:115`), whose own comment says the same.
/// `"N"` is capital-N on the wire; the Swift case is `.skip` so call sites read like the UI.
public enum GateChoice: String, Codable, Sendable, Equatable, CaseIterable {
    case yes = "y"
    case skip = "N"
    case override = "override"
}

/// `POST /api/v1/planning/gate/respond` request body.
public struct GateRespondBody: Codable, Sendable, Equatable {
    public var choice: GateChoice
    public var overrideReason: String
    public var windowDays: Int

    public init(choice: GateChoice, overrideReason: String = "", windowDays: Int = 7) {
        self.choice = choice
        self.overrideReason = overrideReason
        self.windowDays = windowDays
    }

    enum CodingKeys: String, CodingKey {
        case choice
        case overrideReason = "override_reason"
        case windowDays = "window_days"
    }
}

/// `GateRespondOut` — `pdf_requested` + `log_id`. `logId` is Optional because the RN oracle's
/// `GateRespondResult` types it `number | null` (`types.ts:117`) even though today's hub always
/// returns an int; CLAUDE.md rule 5 (never render a zero for missing data) means a missing id
/// must stay nil rather than collapse to 0.
public struct GateRespondResult: Codable, Sendable, Equatable {
    public var pdfRequested: Bool
    public var logId: Int?

    public init(pdfRequested: Bool, logId: Int?) {
        self.pdfRequested = pdfRequested
        self.logId = logId
    }
}

/// `POST /api/v1/planning/feel` request body. `date` nil = "today", decided server-side.
public struct FeelBody: Codable, Sendable, Equatable {
    public var feelScore: Int
    public var notes: String
    public var date: String?

    public init(feelScore: Int, notes: String = "", date: String? = nil) {
        self.feelScore = feelScore
        self.notes = notes
        self.date = date
    }

    enum CodingKeys: String, CodingKey {
        case feelScore = "feel_score"
        case notes
        case date
    }
}

/// `FeelOut` — the inserted `plan.session_feel.feel_id`.
public struct FeelResult: Codable, Sendable, Equatable {
    public var feelId: Int
    public init(feelId: Int) { self.feelId = feelId }
}

/// W-B49B G-3 — `GateAnswerOut` inside `GET /planning/morning` (`gate_answer`): the session-gate
/// answer for the day — the hub's automatic one (`source` "auto", `classification` FULL/GATED,
/// `workout` = the executed activity) or the user's manual one (manual always wins on the hub).
/// String fields on purpose: an unknown value from a newer hub must never fail the whole
/// morning decode — `gateChoice`/`isAutomatic` read them.
public struct GateAnswer: Codable, Sendable, Equatable {
    public var logId: Int
    public var date: String
    public var choice: String
    public var source: String
    public var classification: String?
    public var workout: String?
    public var loggedAt: String?

    public init(logId: Int, date: String, choice: String, source: String,
                classification: String? = nil, workout: String? = nil, loggedAt: String? = nil) {
        self.logId = logId; self.date = date; self.choice = choice; self.source = source
        self.classification = classification; self.workout = workout; self.loggedAt = loggedAt
    }

    public var gateChoice: GateChoice? { GateChoice(rawValue: choice) }
    public var isAutomatic: Bool { source == "auto" }
}

/// G-3: the Today line for an automatic answer — "Answered automatically · GATED from Easy Run"
/// (no workout → just the class). `nil` for a manual answer or none (the "Logged:" row stands).
public func gateAnswerLine(_ answer: GateAnswer?) -> String? {
    guard let answer, answer.isAutomatic else { return nil }
    let cls = answer.classification.map { " · \($0)" } ?? ""
    let from = answer.workout.flatMap { $0.isEmpty ? nil : " from \($0)" } ?? ""
    return "Answered automatically\(cls)\(from)"
}
