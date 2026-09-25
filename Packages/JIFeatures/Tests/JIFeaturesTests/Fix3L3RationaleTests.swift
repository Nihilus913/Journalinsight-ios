import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-FIX3 L3 — BUG-29 (GateRationale header + What counted vs board 03) and BUG-33 (the title
// "Readiness rati…" truncated at AX3).
struct Fix3L3RationaleTests {
    private func s(_ key: String, _ label: String, _ value: Double?, thr: Double, unit: String = "",
                   dir: GateSignalDirection = .min, status: GateSignalStatus, note: String? = nil) -> GateSignal {
        GateSignal(key: key, label: label, value: value, unit: unit, threshold: thr, direction: dir,
                   scaleMin: 0, scaleMax: 100, status: status, note: note)
    }

    private var boardSignals: [GateSignal] {
        [s("sleep_h", "Sleep time", 7.4, thr: 7, unit: "h", status: .pass),
         s("hrv", "HRV", 25, thr: 27, unit: "ms", status: .amber),
         s("rhr", "RHR", nil, thr: 65, unit: "bpm", dir: .max, status: .missing)]
    }

    @Test func noTitleToTruncateTheHeaderCarriesTheWhy() {
        #expect(gateRationaleNavigationTitle.isEmpty)
        #expect(gateRationaleHeaderLabel == "WHY TODAY IS")
    }

    @Test func theWhySentenceSaysWhatPassedAndWhatFlagged() {
        #expect(gateRationaleWhySentence(signals: boardSignals)
                == "Sleep cleared the 7 h goal, overnight HRV is low and resting HR has no reading, so it is left out.")
    }

    @Test func allClearSaysSo() {
        let clear = [s("sleep_h", "Sleep time", 7.4, thr: 7, unit: "h", status: .pass), s("hrv", "HRV", 31, thr: 27, unit: "ms", status: .pass)]
        #expect(gateRationaleWhySentence(signals: clear) == "Sleep cleared the 7 h goal and every other signal is in range.")
        #expect(gateRationaleWhySentence(signals: []) == nil)
        #expect(gateRationaleWhySentence(signals: nil) == nil)
    }

    @Test func whatCountedIsTheFourBoardRowsWithASentenceEach() {
        let rows = gateRationaleCountedRows(signals: boardSignals, normals: ["hrv": 27...30], load: nil)
        #expect(rows.map(\.label) == ["Sleep", "Overnight HRV", "Resting HR", "Load"])
        #expect(rows[0].status == .aboveGoal)
        #expect(rows[0].sentence == "Above your 7 h goal, so intervals and heavy days stay open.")
        #expect(rows[1].sentence == "Under your 27–30 normal.")
        #expect(rows[2].value == nil)
        #expect(rows[2].sentence == "No overnight value yet. Left out, not counted as bad.")
        #expect(rows[3].status == .missing(.calibrating))
        #expect(rows[3].sentence == "No current load reading. Left out.")
    }

    @Test func whatCountedNeverRepeatsDecidesThresholdLines() {
        for row in gateRationaleCountedRows(signals: boardSignals, normals: [:], load: 1.04) {
            #expect(!row.sentence.contains("threshold"))
            #expect(!row.sentence.contains("floor"))
        }
        let load = gateRationaleCountedRows(signals: [], normals: [:], load: 1.04).last
        #expect(load?.value == 1.04)
        #expect(load?.status == .contextOnly)
    }

    @Test func aNormalWithAValueInsideItReadsInside() {
        let row = gateRationaleCountedRows(signals: [s("hrv", "HRV", 29, thr: 27, unit: "ms", status: .pass)], normals: ["hrv": 27...30], load: nil)[0]
        #expect(row.sentence == "Inside your 27–30 normal.")
    }

    /// Sim finding: the live rationale had no "Computed" line (only the by-date branch carried one);
    /// today's persisted verdict row has the time.
    @Test func computedTimeComesFromTodaysVerdictRow() {
        let zurich = TimeZone(identifier: "Europe/Zurich")!
        #expect(gateRationaleComputedTime("2026-09-25T05:41:12.5+00:00", timeZone: zurich) == "07:41")
        #expect(gateRationaleComputedTime(nil, timeZone: zurich) == nil)
    }

    @Test func theRecoveryScoreCalibratingCardIsGone() {
        #expect(gateRationaleLiveSections == [.whatCounted, .weeklyNutrition, .lastDays])
    }
}
