import Foundation

/// W-B57b (B-61, B-62) — the two OPTIONAL fields `GET /api/v1/planning/morning` gains, plus the
/// verdict-override write (`POST/DELETE /api/v1/planning/verdict-override`). Wire contract: Wave
/// Card W-B57b "Contract"; HT source `scripts/morning_go.py` `gate_signals` + `app/planning/router.py`.
///
/// Every wire key here is digit-free snake_case, so `JSON.decoder`'s `.convertFromSnakeCase`
/// yields the synthesized camelCase keys unchanged (no B-48 mangling to spell out).

/// One `morning_go.evaluate` input as the hub scored it. `status` is the hub's verdict on this
/// signal (the app never re-derives it); `value` nil = not synced yet (rule 5: a muted arc + "—",
/// never zero).
public struct GateSignal: Codable, Sendable, Equatable, Identifiable {
    public var key: String
    public var label: String
    public var value: Double?
    public var unit: String
    /// nil when the hub has no threshold for the night (e.g. a missing-HRV signal sends `threshold: null`).
    public var threshold: Double?
    public var direction: GateSignalDirection
    public var status: GateSignalStatus
    public var note: String?
    /// W-SSOT-1 SS-4: the hub's own band for this signal (`band_lo`/`band_hi`) and how it was
    /// derived (`band_method`). Absent/null from an older hub or when the hub has no band.
    public var bandLo: Double?
    public var bandHi: Double?
    public var bandMethod: String?
    /// W-B91 S1 (key "load" only): the hub's named ACWR status — "maintaining" | "productive" |
    /// "overreaching" | "paused" (HT `app/vitals/load_status.py`). Absent from an older hub.
    public var loadStatus: String?
    /// W-B91 S3 b91p2 (key "load" only): the 7 d / 28 d average daily load (effort x hours) behind
    /// the ratio — the Strain sheet's acute / chronic tiles. Absent from an older hub or without a
    /// current ACWR.
    public var acuteLoad: Double?
    public var chronicLoad: Double?

    public var id: String { key }

    /// The hub's band as a range; nil unless both ends are served and ordered.
    public var hubBand: ClosedRange<Double>? {
        guard let lo = bandLo, let hi = bandHi, lo <= hi else { return nil }
        return lo...hi
    }

    public init(
        key: String, label: String, value: Double?, unit: String, threshold: Double?,
        direction: GateSignalDirection,
        status: GateSignalStatus, note: String? = nil,
        bandLo: Double? = nil, bandHi: Double? = nil, bandMethod: String? = nil
    ) {
        self.key = key; self.label = label; self.value = value; self.unit = unit
        self.threshold = threshold; self.direction = direction
        self.status = status; self.note = note
        self.bandLo = bandLo; self.bandHi = bandHi; self.bandMethod = bandMethod
    }
}

/// `"min"` = the value must stay at/above `threshold` (sleep, HRV, sleep time); `"max"` = at/below
/// (RHR). An unknown spelling from a newer hub decodes as `.min` rather than failing the whole
/// morning payload.
public enum GateSignalDirection: String, Codable, Sendable, Equatable {
    case min, max
    public init(from decoder: Decoder) throws {
        self = GateSignalDirection(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .min
    }
}

/// An unknown status from a newer hub decodes as `.missing` (muted) rather than failing the whole
/// morning payload — a signal we cannot classify must never be painted as a pass.
/// `context` (B-65): shown, muted, never gating (daytime HRV).
public enum GateSignalStatus: String, Codable, Sendable, Equatable {
    case pass, amber, red, missing, context
    public init(from decoder: Decoder) throws {
        self = GateSignalStatus(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .missing
    }
}

/// The user's call on the morning verdict (`plan.verdict_override.choice`).
/// accept = keep the verdict · full = the full planned session · modified = the modified session ·
/// rest = rest day.
public enum VerdictOverrideChoice: String, Codable, Sendable, Equatable, CaseIterable {
    case accept, full, modified, rest
}

/// `plan.verdict_override` row as the hub returns it — from the POST and inside `/morning`.
/// `session` is the effective session text the hub resolved for `choice`. `createdAt` is Optional
/// so an optimistic (queued, not yet confirmed) override can be represented locally.
public struct VerdictOverride: Codable, Sendable, Equatable {
    public var date: String
    public var choice: VerdictOverrideChoice
    public var reason: String?
    public var session: String
    public var createdAt: String?

    public init(date: String, choice: VerdictOverrideChoice, reason: String?, session: String, createdAt: String? = nil) {
        self.date = date; self.choice = choice; self.reason = reason
        self.session = session; self.createdAt = createdAt
    }
}

/// `POST /api/v1/planning/verdict-override` body, and the `"verdictOverride"` Outbox payload
/// (both plain `JSONEncoder()`; every key is already the wire spelling).
public struct VerdictOverrideBody: Codable, Sendable, Equatable {
    public var date: String
    public var choice: VerdictOverrideChoice
    public var reason: String

    public init(date: String, choice: VerdictOverrideChoice, reason: String = "") {
        self.date = date; self.choice = choice; self.reason = reason
    }
}

/// The `"verdictOverrideClear"` Outbox payload — an undo (`DELETE …/verdict-override?date=`)
/// queued while the hub was unreachable.
public struct VerdictOverrideClearBody: Codable, Sendable, Equatable {
    public var date: String
    public init(date: String) { self.date = date }
}
