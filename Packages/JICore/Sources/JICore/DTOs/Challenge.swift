import Foundation

/// `plan.gate_challenge` row status (oracle: `ChallengeStatus` in `types.ts`). Only `.active`
/// challenges ever unlock the locked create-time fields (`canEditLockedFields` in
/// `mobile/app/challenges.tsx`) — mirrored by `GateChallenge.canEditLockedFields` below.
public enum ChallengeStatus: String, Codable, Sendable, Equatable {
    case active, completed, archived
}

/// Server-computed progress against the challenge's own `target_sessions` (oracle:
/// `ChallengeProgress` in `types.ts`). `pace` is a purely descriptive label (never evaluative —
/// CLAUDE.md's no-punitive-framing spirit, mirrored from the oracle's `paceLabel` doc comment) and
/// stays optional since the wire type allows `null`.
public struct ChallengeProgress: Codable, Sendable, Equatable {
    public var count: Int
    public var target: Int
    public var executionScore: Int
    public var pace: String?
    public var wantsCompletePrompt: Bool
    public init(count: Int, target: Int, executionScore: Int, pace: String?, wantsCompletePrompt: Bool) {
        self.count = count; self.target = target; self.executionScore = executionScore
        self.pace = pace; self.wantsCompletePrompt = wantsCompletePrompt
    }
}

/// `GET /api/v1/planning/challenges` row (oracle: `GateChallenge` in `types.ts`). Decode-only (the
/// hub is always the source of truth for this shape), so plain auto-generated `CodingKeys` are
/// fine — `JSON.decoder`'s `.convertFromSnakeCase` handles the wire's snake_case.
public struct GateChallenge: Codable, Sendable, Equatable, Identifiable {
    public var challengeId: Int
    public var title: String
    public var hypothesis: String
    public var startDate: String
    public var targetSessions: Int
    public var sessionFilter: String
    public var status: ChallengeStatus
    public var createdAt: String?
    public var completedAt: String?
    public var resultNote: String?
    public var updatedAt: String?
    public var progress: ChallengeProgress

    public var id: Int { challengeId }

    public init(
        challengeId: Int, title: String, hypothesis: String, startDate: String, targetSessions: Int,
        sessionFilter: String, status: ChallengeStatus, createdAt: String?, completedAt: String?,
        resultNote: String?, updatedAt: String?, progress: ChallengeProgress
    ) {
        self.challengeId = challengeId; self.title = title; self.hypothesis = hypothesis
        self.startDate = startDate; self.targetSessions = targetSessions; self.sessionFilter = sessionFilter
        self.status = status; self.createdAt = createdAt; self.completedAt = completedAt
        self.resultNote = resultNote; self.updatedAt = updatedAt; self.progress = progress
    }

    /// FROZEN CONTRACT §2.2 mutability rule (oracle: `canEditLockedFields` in `app/challenges.tsx`):
    /// `target_sessions`/`start_date`/`session_filter` are only PATCHable while the challenge is
    /// still active and has recorded zero sessions — mirrored here so the editor never offers an
    /// edit the hub would reject with a 422, without duplicating the server's own enforcement.
    public var canEditLockedFields: Bool { status == .active && progress.count == 0 }

    /// Oracle `canDelete` (`app/challenges.tsx`): a hard DELETE is only offered when nothing would
    /// be lost — zero recorded sessions and never completed.
    public var canDelete: Bool { progress.count == 0 && completedAt == nil }
}

/// `POST /api/v1/planning/challenges` body (oracle: `ChallengeCreateInput` in `types.ts`, mirrors
/// `app/planning/router.py`'s `ChallengeCreate` exactly). Explicit snake_case `CodingKeys`:
/// `HubClient.send`/`post` encode the outgoing body with a plain `JSONEncoder()` (not
/// `JSON.encoder`'s `.convertToSnakeCase`), so this type must already be snake_case on the wire —
/// same convention as `ExerciseUpdate` (`DTOs/Training.swift`).
public struct ChallengeCreateInput: Encodable, Sendable, Equatable {
    public var title: String
    public var hypothesis: String
    public var startDate: String
    public var targetSessions: Int
    public var sessionFilter: String
    public init(title: String, hypothesis: String, startDate: String, targetSessions: Int, sessionFilter: String = "interval") {
        self.title = title; self.hypothesis = hypothesis; self.startDate = startDate
        self.targetSessions = targetSessions; self.sessionFilter = sessionFilter
    }
    private enum CodingKeys: String, CodingKey {
        case title, hypothesis
        case startDate = "start_date"
        case targetSessions = "target_sessions"
        case sessionFilter = "session_filter"
    }
}

/// `PATCH /api/v1/planning/challenges/{id}` body (oracle: `ChallengeUpdateInput` in `types.ts`,
/// mirrors `ChallengeUpdate` — `extra="forbid"`, so only these keys). No `status`/`end_date` field
/// on purpose (FROZEN CONTRACT §2.2 — status transitions stay on the archive endpoint / DELETE).
/// `nil` on every field means "send an empty patch" — callers build this by diffing against the
/// current row (mirrors the oracle's `EditChallengeForm.submit`), so only changed fields are ever
/// included; a genuinely-cleared result note is sent as an explicit empty string rather than a
/// nested null (this port does not model the tri-state "omit vs explicit null" the oracle's
/// `string | null` allows — noted as a scope simplification).
public struct ChallengeUpdatePatch: Encodable, Sendable, Equatable {
    public var title: String?
    public var hypothesis: String?
    public var targetSessions: Int?
    public var startDate: String?
    public var sessionFilter: String?
    public var resultNote: String?
    public init(
        title: String? = nil, hypothesis: String? = nil, targetSessions: Int? = nil,
        startDate: String? = nil, sessionFilter: String? = nil, resultNote: String? = nil
    ) {
        self.title = title; self.hypothesis = hypothesis; self.targetSessions = targetSessions
        self.startDate = startDate; self.sessionFilter = sessionFilter; self.resultNote = resultNote
    }
    private enum CodingKeys: String, CodingKey {
        case title, hypothesis
        case targetSessions = "target_sessions"
        case startDate = "start_date"
        case sessionFilter = "session_filter"
        case resultNote = "result_note"
    }
    /// Omits absent fields entirely (rather than encoding explicit `null`s) so a diff-only patch
    /// never re-sends a locked key the hub would reject — mirrors the oracle building
    /// `ChallengeUpdateInput` by only setting keys that actually changed.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(hypothesis, forKey: .hypothesis)
        try c.encodeIfPresent(targetSessions, forKey: .targetSessions)
        try c.encodeIfPresent(startDate, forKey: .startDate)
        try c.encodeIfPresent(sessionFilter, forKey: .sessionFilter)
        try c.encodeIfPresent(resultNote, forKey: .resultNote)
    }
}

/// `status` argument to `POST /api/v1/planning/challenges/{id}/archive` (oracle:
/// `ChallengeArchiveStatus` in `types.ts`).
public enum ChallengeArchiveStatus: String, Sendable, Equatable {
    case completed, archived
}

/// `POST /api/v1/planning/challenges/{id}/archive` body (oracle: `ChallengeArchiveBody` in
/// `app/planning/router.py`). `resultNote` omitted (not sent as null) leaves any existing
/// `result_note` untouched server-side, per the router's own doc comment.
public struct ChallengeArchiveBody: Encodable, Sendable, Equatable {
    public var status: ChallengeArchiveStatus
    public var resultNote: String?
    public init(status: ChallengeArchiveStatus, resultNote: String? = nil) {
        self.status = status; self.resultNote = resultNote
    }
    private enum CodingKeys: String, CodingKey {
        case status
        case resultNote = "result_note"
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(status.rawValue, forKey: .status)
        try c.encodeIfPresent(resultNote, forKey: .resultNote)
    }
}

/// `GET /api/v1/planning/challenges` envelope (oracle: `ChallengesResponse`).
public struct ChallengesResponse: Decodable, Sendable, Equatable {
    public var challenges: [GateChallenge]
    public init(challenges: [GateChallenge]) { self.challenges = challenges }
}
