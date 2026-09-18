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
