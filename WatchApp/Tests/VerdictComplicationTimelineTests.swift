import Foundation
import Testing
import JISnapshot
@testable import WatchApp

/// B-10: covers `complicationTimelineEntries` — the complication's entry
/// updates when the underlying snapshot changes, and falls back to a muted
/// placeholder (never a fabricated verdict) when there's no snapshot or the
/// snapshot is stale.
@Suite
struct VerdictComplicationTimelineTests {
    static func snapshot(word: String, tone: String, lastSync: Date?) -> HubSnapshot {
        HubSnapshot(
            verdictWord: word,
            verdictSession: "",
            verdictTone: tone,
            verdictDate: "2026-09-17",
            readiness: 70,
            kpis: [],
            fetchedAt: Date(timeIntervalSince1970: 1_757_000_000),
            lastSync: lastSync
        )
    }

    @Test
    func noSnapshotProducesMutedPlaceholder() {
        let entries = complicationTimelineEntries(from: nil)
        #expect(entries.count == 1)
        #expect(entries[0].verdictWord == "—")
        #expect(entries[0].tone == "muted")
    }

    @Test
    func timelineEntryUpdatesWhenSnapshotChanges() {
        let now = Date(timeIntervalSince1970: 1_757_100_000)
        let go = Self.snapshot(word: "GO", tone: "go", lastSync: now)
        let reduced = Self.snapshot(word: "REDUCED", tone: "amber", lastSync: now)

        let goEntries = complicationTimelineEntries(from: go, now: now)
        let reducedEntries = complicationTimelineEntries(from: reduced, now: now)

        #expect(goEntries.first?.verdictWord == "GO")
        #expect(goEntries.first?.tone == "go")
        #expect(reducedEntries.first?.verdictWord == "REDUCED")
        #expect(reducedEntries.first?.tone == "amber")
        #expect(goEntries != reducedEntries)
    }

    @Test
    func staleSnapshotOverridesToneToMutedButKeepsTheWord() {
        let now = Date(timeIntervalSince1970: 1_757_100_000)
        let staleSync = now.addingTimeInterval(-37 * 3600) // > 36h
        let stale = Self.snapshot(word: "GO", tone: "go", lastSync: staleSync)

        let entries = complicationTimelineEntries(from: stale, now: now)

        #expect(entries.first?.verdictWord == "GO")
        #expect(entries.first?.tone == "muted")
    }
}
