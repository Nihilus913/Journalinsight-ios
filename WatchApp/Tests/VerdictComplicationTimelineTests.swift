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

extension VerdictComplicationTimelineTests {
    static func w5() -> HubSnapshot {
        HubSnapshot(verdictWord: "Full", verdictSession: "Day 2 · Upper", verdictTone: "go", verdictDate: "2026-09-23",
                    readiness: 78, kpis: [], fetchedAt: .now, lastSync: .now,
                    reason: "HRV 25 ms — under 27", planDone: 2, planTotal: 4, hrCap: 172,
                    signals: [SnapshotSignal(key: "hrv", label: "HRV", value: 25, unit: "ms", normalLow: 27, normalHigh: 30, goal: nil, status: "amber")])
    }

    @Test func entryCarriesPlanCapAndDetail() throws {
        let e = try #require(complicationTimelineEntries(from: Self.w5(), now: .now).first)
        #expect(e.session == "Day 2 · Upper")
        #expect(e.planText == "2 of 4" && e.planFraction == 0.5)
        #expect(e.hrCap == 172 && e.capSlot == "cap 172")
        #expect(e.detail == "HRV 25 < 27")
    }

    /// Toby 2026-09-24: no cap ⇒ the cap's slot shows the next session.
    @Test func noCapShowsTheNextSession() throws {
        var s = Self.w5()
        s.hrCap = nil
        s.nextSession = "Fri · Day 3 Full Upper"
        let e = try #require(complicationTimelineEntries(from: s, now: .now).first)
        #expect(e.hrCap == nil && e.capSlot == "next Fri")
        #expect(complicationInlineText(e) == "Full · next Fri")
        s.nextSession = nil
        let bare = try #require(complicationTimelineEntries(from: s, now: .now).first)
        #expect(bare.capSlot == nil && complicationInlineText(bare) == "Full")
    }

    @Test func rectDetailFallsBackToReasonThenNothing() {
        var s = Self.w5()
        s.signals = nil
        #expect(complicationRectDetail(s) == "HRV 25 ms — under 27")
        s.reason = nil
        #expect(complicationRectDetail(s) == nil)
    }

    @Test func noSnapshotShowsNoCap() throws {
        let e = try #require(complicationTimelineEntries(from: nil).first)
        #expect(e.hrCap == nil && e.capSlot == nil && e.planText == nil && e.verdictWord == "—")
    }
}
