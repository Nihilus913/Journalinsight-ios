import Foundation
import GRDB
import Testing
@testable import JIPersistence

/// W-ONDEVICE O-10 (B-44 dual run): each morning's on-device verdict next to the hub's, in
/// `DecisionLogStore`. Exit for B-20 = 14 matching days.
@Suite struct ShadowVerdictLogTests {
    private func row(_ day: String, onDevice: String, hub: String?, latency: Double? = 600) -> ShadowVerdictRow {
        ShadowVerdictRow(day: day, onDeviceVerdict: onDevice, hubVerdict: hub, inputsDigest: "abc123",
                         computedAt: "\(day)T05:00:00Z", latencyFromWakeSec: latency)
    }

    @Test func migrationCreatesTheShadowTable() throws {
        let db = try AppDatabase.inMemory()
        let columns = try db.pool.read { try $0.columns(in: "ondevice_shadow_log").map(\.name) }
        #expect(columns == ["day", "ondevice_verdict", "hub_verdict", "inputs_digest", "computed_at", "latency_from_wake_sec"])
    }

    @Test func diffRowsAreCountedByVerdictClass() throws {
        let store = DecisionLogStore(db: try AppDatabase.inMemory())
        try store.recordShadow(row("2026-10-01", onDevice: "GO — Strength A", hub: "GO — Strength A"))
        // Same class, different session text: not a diff (the bar is the same Go/Modify/Rest).
        try store.recordShadow(row("2026-10-02", onDevice: "GO — Strength A", hub: "GO (recovery 61) — Strength B"))
        try store.recordShadow(row("2026-10-03", onDevice: "MODIFY — Z2 only", hub: "GO — Strength A"))
        let parity = try store.shadowParity()
        #expect(parity == ShadowParity(days: 3, diffs: 1, hubMissing: 0))
    }

    @Test func latencyIsRecorded() throws {
        let store = DecisionLogStore(db: try AppDatabase.inMemory())
        try store.recordShadow(row("2026-10-04", onDevice: "GO — A", hub: nil, latency: 754.5))
        #expect(try store.shadowRows(limit: 5).first?.latencyFromWakeSec == 754.5)
    }

    @Test func noHubLeavesTheHubColumnNilAndOutOfTheParityCount() throws {
        let store = DecisionLogStore(db: try AppDatabase.inMemory())
        try store.recordShadow(row("2026-10-04", onDevice: "GO — A", hub: nil))
        let rows = try store.shadowRows(limit: 5)
        #expect(rows.first?.hubVerdict == nil)
        #expect(try store.shadowParity() == ShadowParity(days: 0, diffs: 0, hubMissing: 1))
    }

    @Test func aRecomputedMorningReplacesItsRowAndKeepsAKnownHubVerdict() throws {
        let store = DecisionLogStore(db: try AppDatabase.inMemory())
        try store.recordShadow(row("2026-10-04", onDevice: "GO — A", hub: "GO — A"))
        try store.recordShadow(row("2026-10-04", onDevice: "MODIFY — Z2", hub: nil))
        let rows = try store.shadowRows(limit: 5)
        #expect(rows.count == 1)
        #expect(rows[0].onDeviceVerdict == "MODIFY — Z2")
        #expect(rows[0].hubVerdict == "GO — A")
    }

    @Test func verdictClassIsTheLeadingWord() {
        #expect(ShadowParity.verdictClass("GO (recovery 61) — Strength B") == "GO")
        #expect(ShadowParity.verdictClass("REST") == "REST")
        #expect(ShadowParity.verdictClass("modify — z2") == "MODIFY")
    }

    @Test func rowsAreNewestFirst() throws {
        let store = DecisionLogStore(db: try AppDatabase.inMemory())
        try store.recordShadow(row("2026-10-02", onDevice: "GO — A", hub: "GO — A"))
        try store.recordShadow(row("2026-10-04", onDevice: "GO — A", hub: "GO — A"))
        #expect(try store.shadowRows(limit: 1).map(\.day) == ["2026-10-04"])
    }
}
