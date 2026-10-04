import Foundation
import GRDB

/// W-ONDEVICE O-10 (B-44 dual run): one morning's on-device verdict next to the hub's.
public struct ShadowVerdictRow: Sendable, Equatable {
    public var day: String
    public var onDeviceVerdict: String
    /// nil = no hub (or the hub had no verdict for the day yet).
    public var hubVerdict: String?
    /// Digest of the nightly inputs the on-device compute read (replays are comparable).
    public var inputsDigest: String
    /// ISO-8601 time the on-device verdict was computed.
    public var computedAt: String
    /// Seconds from the night's wake (main sleep end) to `computedAt`; nil when unknown.
    public var latencyFromWakeSec: Double?

    public init(day: String, onDeviceVerdict: String, hubVerdict: String?, inputsDigest: String, computedAt: String, latencyFromWakeSec: Double?) {
        self.day = day; self.onDeviceVerdict = onDeviceVerdict; self.hubVerdict = hubVerdict
        self.inputsDigest = inputsDigest; self.computedAt = computedAt; self.latencyFromWakeSec = latencyFromWakeSec
    }
}

/// "parity N days, M diffs": `days` = mornings with both verdicts, `diffs` = of those, a different
/// Go/Modify/Rest class; `hubMissing` = mornings with no hub verdict (not counted either way).
public struct ShadowParity: Sendable, Equatable {
    public var days: Int
    public var diffs: Int
    public var hubMissing: Int
    public init(days: Int, diffs: Int, hubMissing: Int) { self.days = days; self.diffs = diffs; self.hubMissing = hubMissing }

    /// The verdict's class — its leading word (`GO`, `MODIFY`, `REST`, `REDUCED`, `RED`), upper-cased;
    /// the session text and any parenthetical never make a diff (O-10's bar: same gate outcome).
    public static func verdictClass(_ verdict: String) -> String {
        let letters = verdict.trimmingCharacters(in: .whitespaces).prefix { $0.isLetter }
        return letters.uppercased()
    }
}

extension DecisionLogStore {
    /// Upserts the morning's row (a recompute replaces it); a known hub verdict is kept when the
    /// new row has none (the hub may have been unreachable on the later run).
    public func recordShadow(_ row: ShadowVerdictRow) throws {
        try db.pool.write { db in
            try db.execute(sql: """
                INSERT INTO ondevice_shadow_log (day, ondevice_verdict, hub_verdict, inputs_digest, computed_at, latency_from_wake_sec)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(day) DO UPDATE SET
                  ondevice_verdict = excluded.ondevice_verdict,
                  hub_verdict = COALESCE(excluded.hub_verdict, ondevice_shadow_log.hub_verdict),
                  inputs_digest = excluded.inputs_digest,
                  computed_at = excluded.computed_at,
                  latency_from_wake_sec = COALESCE(excluded.latency_from_wake_sec, ondevice_shadow_log.latency_from_wake_sec)
                """, arguments: [row.day, row.onDeviceVerdict, row.hubVerdict, row.inputsDigest, row.computedAt, row.latencyFromWakeSec])
        }
    }

    /// Newest first.
    public func shadowRows(limit: Int) throws -> [ShadowVerdictRow] {
        try db.pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT day, ondevice_verdict, hub_verdict, inputs_digest, computed_at, latency_from_wake_sec
                FROM ondevice_shadow_log ORDER BY day DESC LIMIT ?
                """, arguments: [limit]).map { r in
                ShadowVerdictRow(day: r["day"], onDeviceVerdict: r["ondevice_verdict"], hubVerdict: r["hub_verdict"],
                                 inputsDigest: r["inputs_digest"], computedAt: r["computed_at"], latencyFromWakeSec: r["latency_from_wake_sec"])
            }
        }
    }

    /// Parity over every logged morning.
    public func shadowParity() throws -> ShadowParity {
        let rows = try shadowRows(limit: Int.max)
        var parity = ShadowParity(days: 0, diffs: 0, hubMissing: 0)
        for row in rows {
            guard let hub = row.hubVerdict else { parity.hubMissing += 1; continue }
            parity.days += 1
            if ShadowParity.verdictClass(hub) != ShadowParity.verdictClass(row.onDeviceVerdict) { parity.diffs += 1 }
        }
        return parity
    }
}
