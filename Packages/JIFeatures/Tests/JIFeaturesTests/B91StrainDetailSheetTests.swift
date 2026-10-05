import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-B91 S3 b91p2: the Strain detail sheet model — strain + usual range, the Exercise-minutes Load
// figure (Q4), three ACWR fact tiles and the named status word next to the ratio.
@Suite struct B91StrainDetailSheetTests {
    private func strain(status: String = "ok", yesterday: Double? = 47, today: Double? = 12) -> MorningStrain {
        MorningStrain(status: status, loadedDays: status == "ok" ? 43 : 12, usualLow: status == "ok" ? 30 : nil,
                      usualHigh: status == "ok" ? 55 : nil,
                      yesterday: .init(date: "2026-10-04", value: yesterday, sessions: [.init(name: "Outdoor Run", minutes: 48)]),
                      today: .init(date: "2026-10-05", value: today))
    }

    private func load(_ status: String? = "overreaching", value: Double? = 1.84,
                      acute: Double? = 1.21, chronic: Double? = 0.66) -> GateSignal {
        var s = GateSignal(key: "load", label: "Load", value: value, unit: "", threshold: nil, direction: .max,
                           status: .context, note: "7 d vs 28 d · 6 sessions in 28 d · 0.80–1.30 is productive")
        s.loadStatus = status; s.acuteLoad = acute; s.chronicLoad = chronic
        return s
    }

    private let minutes = RecoveryLoadReading(minutes: 245, normal: nil, points: [])

    @Test func sheetHasStrainUsualMinutesThreeTilesAndWord() {
        let st = decideStrainState(strain: strain(), override: nil, verdict: verdictParts("GO — Strength B"))
        let m = strainDetailModel(state: st, strain: strain(), load: load(), minutes: minutes)
        #expect(m.strainLabel == "Yesterday" && m.strainText == "47")
        #expect(m.usualText == "Your usual 30–55")
        #expect(m.minutesText == "245 min")
        #expect(m.minutesCaption == "Exercise minutes · 7 d · Calibrating")
        #expect(m.tiles.map(\.id) == ["acute", "chronic", "ratio"])
        #expect(m.tiles.map(\.valueText) == ["1.21", "0.66", "1.84"])
        #expect(m.statusWord == "Overreaching" && m.status == .overreaching)
        #expect(m.statusCaption == "7 d vs 28 d · 6 sessions in 28 d · 0.80–1.30 is productive")
    }

    @Test func afterTheCallShowsTodayAndKeepsTheUsualRange() {
        let ov = VerdictOverride(date: "2026-10-05", choice: .accept, reason: nil, session: "", createdAt: "2026-10-05T06:00:00Z")
        let st = decideStrainState(strain: strain(), override: ov, verdict: verdictParts("GO — Strength B"))
        let m = strainDetailModel(state: st, strain: strain(), load: load("productive", value: 1.07), minutes: minutes)
        #expect(m.strainLabel == "Today so far" && m.strainText == "12")
        #expect(m.usualText == "Your usual 30–55")
        #expect(m.statusWord == "Productive")
    }

    @Test func pausedReadsPausedEvenWithoutARatio() {
        let st = decideStrainState(strain: strain(), override: nil, verdict: verdictParts("GO — x"))
        let m = strainDetailModel(state: st, strain: strain(), load: load("paused", value: nil, acute: nil, chronic: nil), minutes: nil)
        #expect(m.statusWord == "Paused")
        #expect(m.tiles.map(\.valueText) == ["—", "—", "—"])
        #expect(m.minutesText == "—" && m.minutesCaption == "Exercise minutes · No data")
    }

    @Test func calibratingAndNoLoadRowStayHonest() {
        let s = strain(status: "calibrating", yesterday: nil, today: nil)
        let st = decideStrainState(strain: s, override: nil, verdict: verdictParts("GO — x"))
        let m = strainDetailModel(state: st, strain: s, load: nil, minutes: minutes)
        #expect(m.strainText == "—")
        #expect(m.usualText == "Calibrating · 12 of 19 loaded days")
        #expect(m.tiles.count == 3)
        #expect(m.statusWord == "No data")
        #expect(m.minutesText == "245 min")
    }

    @Test func loadSignalIsPickedByKey() {
        let rhr = GateSignal(key: "rhr", label: "RHR", value: 55, unit: "bpm", threshold: 65, direction: .max, status: .pass)
        #expect(strainDetailLoadSignal([rhr, load()])?.key == "load")
        #expect(strainDetailLoadSignal([rhr]) == nil && strainDetailLoadSignal(nil) == nil)
    }
}
