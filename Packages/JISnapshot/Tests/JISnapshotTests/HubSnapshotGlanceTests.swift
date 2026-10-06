import Foundation
import Testing
import JICore
@testable import JISnapshot

@Suite
struct HubSnapshotGlanceTests {
    static func w5Snapshot() -> HubSnapshot {
        HubSnapshot(
            verdictWord: "GO", verdictSession: "Day 2 · Full Upper", verdictTone: "go", verdictDate: "2026-09-23",
            readiness: 78,
            kpis: [SnapshotKPI(label: "HRV", value: 25, unit: "ms")],
            allKpis: [SnapshotKPI(id: .hrv, label: "HRV", value: 25, unit: "ms", normalLow: 27, normalHigh: 30)],
            fetchedAt: Date(timeIntervalSince1970: 1_758_600_000), lastSync: Date(timeIntervalSince1970: 1_758_599_000),
            reason: "HRV 25 ms — under 27", planDone: 2, planTotal: 4, hrCap: 180, nextSession: "Fri · Day 3 Full Upper",
            signals: [SnapshotSignal(key: "hrv", label: "HRV", value: 25, unit: "ms", normalLow: 27, normalHigh: 30, goal: nil, status: "amber")]
        )
    }

    private func json(_ s: HubSnapshot) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
    }
    private func decode(_ obj: [String: Any]) throws -> HubSnapshot {
        try JSONDecoder().decode(HubSnapshot.self, from: JSONSerialization.data(withJSONObject: obj))
    }

    @Test func roundTripsEveryW5Field() throws {
        let s = Self.w5Snapshot()
        #expect(try JSONDecoder().decode(HubSnapshot.self, from: JSONEncoder().encode(s)) == s)
    }

    @Test func oldPayloadDecodes() throws {
        var obj = try json(Self.w5Snapshot())
        for k in ["reason", "planDone", "planTotal", "hrCap", "nextSession", "signals", "macros"] { obj.removeValue(forKey: k) }
        var kpis = try #require(obj["allKpis"] as? [[String: Any]])
        kpis[0].removeValue(forKey: "normalLow"); kpis[0].removeValue(forKey: "normalHigh")
        obj["allKpis"] = kpis
        let old = try decode(obj)
        #expect(old.verdictWord == "GO")
        #expect(old.reason == nil && old.planDone == nil && old.planTotal == nil && old.nextSession == nil && old.signals == nil)
        #expect(old.hrCap == nil)                         // an old payload never had a cap: none is invented
        #expect(old.allKpis?.first?.normalLow == nil)
    }

    @Test func malformedW5FieldKeepsTheSnapshot() throws {
        var obj = try json(Self.w5Snapshot())
        obj["planDone"] = "two"; obj["hrCap"] = "high"; obj["signals"] = 7
        let s = try decode(obj)
        #expect(s.verdictWord == "GO")
        #expect(s.planDone == nil && s.hrCap == nil && s.signals == nil)
        #expect(s.planTotal == 4)
    }

    /// Toby 2026-09-24: the cap is optional user input — shown only when set, never a fallback.
    @Test func hrCapIsShownOnlyWhenSet() {
        var s = Self.w5Snapshot()
        #expect(s.hrCap == 180 && s.capText == "cap 180" && s.capSlotText == "cap 180")
        s.hrCap = nil
        #expect(s.capText == nil)
        #expect(s.capSlotText == "next Fri")              // no cap: the slot shows the next session
        s.nextSession = nil
        #expect(s.capSlotText == nil)
        let noCap = HubSnapshot(verdictWord: "GO", verdictSession: "Day 2 · Full Upper", verdictTone: "go", verdictDate: "2026-09-23",
                                readiness: 78, kpis: [], allKpis: nil, fetchedAt: .now, lastSync: .now, reason: nil, planDone: 2, planTotal: 4)
        #expect(noCap.hrCap == nil)                       // the init default is "no cap", not 175
    }

    static func sig(_ key: String, _ status: GateSignalStatus, note: String? = nil, label: String = "HRV") -> GateSignal {
        GateSignal(key: key, label: label, value: 25, unit: "ms", threshold: 27, direction: .min, status: status, note: note)
    }

    @Test func reasonPrefersRedThenAmber() {
        let signals = [Self.sig("sleep_h", .amber, note: "6.1 h sleep — under 7 h", label: "Sleep time"),
                       Self.sig("hrv", .red, note: "HRV 22 ms — low 2 nights", label: "HRV")]
        #expect(HubSnapshot.reasonLine(from: signals) == "HRV 22 ms — low 2 nights")
        #expect(HubSnapshot.reasonLine(from: [signals[0]]) == "6.1 h sleep — under 7 h")
    }

    @Test func reasonNilWhenNothingHeldBack() {
        #expect(HubSnapshot.reasonLine(from: nil) == nil)
        #expect(HubSnapshot.reasonLine(from: [Self.sig("hrv", .pass), Self.sig("hrv_day", .context), Self.sig("rhr", .missing)]) == nil)
    }

    @Test func reasonFallsBackToLabelWhenNoteIsBlank() {
        #expect(HubSnapshot.reasonLine(from: [Self.sig("hrv", .amber, note: "  ", label: "HRV")]) == "HRV low")
        #expect(HubSnapshot.reasonLine(from: [Self.sig("rhr", .red, note: nil, label: "RHR")]) == "RHR red")
    }

    @Test func reasonClipsAt48() {
        let long = String(repeating: "é", count: 60)
        let clipped = try! #require(HubSnapshot.reasonLine(from: [Self.sig("hrv", .amber, note: long)]))
        #expect(clipped.count == 48)
        #expect(clipped.hasSuffix("…"))
        let s = HubSnapshot(verdictWord: "GO", verdictSession: "", verdictTone: "go", verdictDate: nil, readiness: nil, kpis: [],
                            fetchedAt: .now, lastSync: nil, reason: long)
        #expect(s.reason?.count == 48)
        #expect(HubSnapshot.clipReason("   ") == nil)
    }

    @Test func planAndNextSessionText() {
        var s = Self.w5Snapshot()
        #expect(s.planProgressText == "2 of 4")
        #expect(s.planFraction == 0.5)
        #expect(s.nextSessionDay == "Fri")
        s.planDone = nil
        #expect(s.planProgressText == "— of 4")
        #expect(s.planFraction == nil)
        s.planTotal = 0
        #expect(s.planProgressText == nil)
        s.nextSession = nil
        #expect(s.nextSessionDay == nil)
    }

    @Test func inlineTextUsesReasonElseSession() {
        var s = Self.w5Snapshot()
        #expect(s.inlineGlanceText == "GO · HRV 25 ms — under 27")
        s.reason = nil
        #expect(s.inlineGlanceText == "GO · Day 2 · Full Upper")
    }

    @Test func signalWordsAndCaptions() {
        let hrv = SnapshotSignal(key: "hrv", label: "HRV", value: 25, unit: "ms", normalLow: 27, normalHigh: 30, goal: nil, status: "amber")
        #expect(hrv.word == "Low" && hrv.caption == "normal 27–30" && hrv.valueText == "25")
        #expect(hrv.compactComparison == "HRV 25 < 27")
        let inNormal = SnapshotSignal(key: "hrv", label: "HRV", value: 28, unit: "ms", normalLow: 27, normalHigh: 30, goal: nil, status: "pass")
        #expect(inNormal.word == "In normal" && inNormal.compactComparison == nil)
        let high = SnapshotSignal(key: "rhr", label: "RHR", value: 62, unit: "bpm", normalLow: 50, normalHigh: 56, goal: nil, status: "amber")
        #expect(high.word == "High" && high.compactComparison == "RHR 62 > 56")
        let sleep = SnapshotSignal(key: "sleep_h", label: "Sleep", value: 7.4, unit: "h", normalLow: nil, normalHigh: nil, goal: 7, status: "pass")
        #expect(sleep.word == "Enough" && sleep.caption == "goal 7.0 h" && sleep.valueText == "7.4")
        let short = SnapshotSignal(key: "sleep_h", label: "Sleep", value: 6.2, unit: "h", normalLow: nil, normalHigh: nil, goal: 7, status: "amber")
        #expect(short.word == "Below goal")
        let none = SnapshotSignal(key: "rhr", label: "Resting HR", value: nil, unit: "bpm", normalLow: nil, normalHigh: nil, goal: nil, status: "missing")
        #expect(none.word == "No reading" && none.caption == "left out" && none.valueText == "—")
        let calibrating = SnapshotSignal(key: "hrv", label: "HRV", value: 25, unit: "ms", normalLow: nil, normalHigh: nil, goal: nil, status: "amber")
        #expect(calibrating.word == "Caution" && calibrating.caption == "Calibrating")
    }

    @Test func glanceSignalsAlwaysThreeInOrder() {
        let out = GlanceSignals.make(
            gateSignals: [GateSignal(key: "sleep_h", label: "Sleep time", value: 7.4, unit: "h", threshold: 7, direction: .min, status: .pass),
                          Self.sig("hrv", .amber)],
            hrvNormal: 27...30, rhrNormal: nil, sleepGoalH: 7)
        #expect(out.map(\.key) == ["hrv", "sleep_h", "rhr"])
        #expect(out[0].normalLow == 27 && out[0].normalHigh == 30 && out[0].status == "amber")
        #expect(out[1].goal == 7 && out[1].label == "Sleep")
        #expect(out[2].value == nil && out[2].status == "missing" && out[2].label == "Resting HR")
        #expect(GlanceSignals.make(gateSignals: nil, hrvNormal: nil, rhrNormal: nil, sleepGoalH: nil).allSatisfy { $0.status == "missing" })
    }

    /// W-B57-W5 fixer (glance-RHR): the gate never sends RHR, so the triple's RHR read "No reading"
    /// with today's RHR on Recovery. A reading the gate did not judge comes from `latest` as
    /// "context" (the band still words it); the gate's own signal wins when both exist.
    @Test func glanceSignalsTakeTheLatestReadingTheGateDidNotSend() {
        let out = GlanceSignals.make(gateSignals: [Self.sig("hrv", .amber)], hrvNormal: nil, rhrNormal: 55...65,
                                     sleepGoalH: 7, latest: ["rhr": 71, "hrv": 99])
        #expect(out[2].value == 71 && out[2].status == "context")
        #expect(out[2].word == "High" && out[2].caption == "normal 55–65")
        #expect(out[0].status == "amber" && out[0].value != 99)          // the gate's HRV wins
        #expect(out[1].status == "missing")                              // no sleep anywhere: still left out
    }

    /// W-B57-W5 fixer (A2 medium): the medium face's three columns truncated "Below…", "No rea…",
    /// "Restin…", "normal 2…". Its compact vocabulary fits a ~48 pt column and stays honest.
    @Test func compactSignalVocabularyFitsTheMediumColumn() {
        let rhr = SnapshotSignal(key: "rhr", label: "Resting HR", value: nil, unit: "bpm", normalLow: nil, normalHigh: nil, goal: nil, status: "missing")
        #expect(rhr.shortLabel == "RHR" && rhr.compactWord == "None" && rhr.compactCaption == "left out")
        let sleep = SnapshotSignal(key: "sleep_h", label: "Sleep", value: 6.2, unit: "h", normalLow: nil, normalHigh: nil, goal: 7, status: "amber")
        #expect(sleep.compactWord == "Short" && sleep.compactCaption == "goal 7.0")
        let hrv = SnapshotSignal(key: "hrv", label: "HRV", value: 28, unit: "ms", normalLow: 27, normalHigh: 30, goal: nil, status: "pass")
        #expect(hrv.shortLabel == "HRV" && hrv.compactWord == "Normal" && hrv.compactCaption == "27–30")
        let calibrating = SnapshotSignal(key: "hrv", label: "HRV", value: 25, unit: "ms", normalLow: nil, normalHigh: nil, goal: nil, status: "red")
        #expect(calibrating.compactWord == "Red" && calibrating.compactCaption == "no normal")
        for s in [rhr, sleep, hrv, calibrating] {
            #expect(s.shortLabel.count <= 6 && s.compactWord.count <= 6 && s.compactCaption.count <= 9)
        }
    }

    @Test func kpiBandWord() {
        let k = SnapshotKPI(id: .hrv, label: "HRV", value: 25, unit: "ms", normalLow: 27, normalHigh: 30)
        #expect(k.bandWord == "Low" && k.normalCaption == "normal 27–30")
        #expect(SnapshotKPI(id: .hrv, label: "HRV", value: 25, unit: "ms").bandWord == nil)
        #expect(SnapshotKPI(id: .hrv, label: "HRV", value: nil, unit: "ms", normalLow: 27, normalHigh: 30).bandWord == nil)
    }
}
