import Testing
import JICore
import JIDesign
@testable import JIFeatures

// B-57 W1 (B-72): the Decide why-row is SignalRows. W1 has no personal normal, so the status word
// is the hub's pass/amber/red in words and the reference line is the hub threshold. Sleep keeps
// the FLOOR wording (spec §0.3: "goal" wording waits for W3).
struct DecideSignalsTests {
    private func s(_ key: String, _ value: Double?, thr: Double, unit: String = "", status: GateSignalStatus, note: String? = nil) -> GateSignal {
        GateSignal(key: key, label: key.uppercased(), value: value, unit: unit, threshold: thr, direction: .min,
                   status: status, note: note)
    }

    @Test func hubStatusBecomesAWord() {
        #expect(decideSignalStatus(s("hrv", 25, thr: 27, status: .amber)) == .watch)
        #expect(decideSignalStatus(s("hrv", 31, thr: 27, status: .pass)) == .clear)
        #expect(decideSignalStatus(s("rhr", 70, thr: 65, status: .red)) == .redFlag)
    }

    @Test func decideRowMissingValueIsNoDataNeverZero() {
        let m = decideSignalRowModel(s("rhr", nil, thr: 65, unit: "bpm", status: .missing))
        #expect(m.value == nil)
        #expect(m.status == .missing(.noData))
        // a nil value with a stale non-missing status is still "No data" — never a painted pass
        #expect(decideSignalStatus(s("rhr", nil, thr: 65, status: .pass)) == .missing(.noData))
    }

    @Test func decideRowContextIsContextOnly() {
        let m = decideSignalRowModel(s("hrv_day", 14, thr: 0, unit: "ms", status: .context, note: "Concerta hours · not used"))
        #expect(m.status == .contextOnly)
        #expect(m.detail == "Concerta hours · not used")
    }

    /// W-FIX3 BUG-30 (board 01): sleep time reads as the goal it is gated on ("goal 7 h").
    @Test func sleepReadsAsItsGoal() {
        // W-TGT L3 (D2): "goal 7 h" once the user typed 7 in Targets.
        let m = decideSignalRowModel(s("sleep_h", 7.4, thr: 7, unit: "h", status: .pass), sleepGoalH: 7)
        #expect(m.detail == "goal 7 h")
        #expect(m.decimals == 1)
        #expect(!(m.detail ?? "").contains("floor"))
    }

    /// W-FIX3 BUG-30: no "threshold" line — the normal, or "calibrating" until there is one.
    @Test func otherSignalsShowTheirNormalNotAThreshold() {
        #expect(decideSignalRowModel(s("hrv", 25, thr: 27, unit: "ms", status: .amber)).detail == "your normal — Calibrating")
        #expect(decideSignalRowModel(s("sleep", 74, thr: 70, status: .pass), normal: 70...85).normal == 70...85)
    }
}

extension DecideSignalsTests {
    @Test func sessionRowNamesTheSessionOrSaysNoData() {
        let v = verdictParts("GO — Full Upper")   // VerdictParts's memberwise init is JICore-internal
        #expect(decideSessionRowText(sessionForToday: "Day 2 · Full Upper", verdict: v) == ("Today's session", "Day 2 · Full Upper"))
        #expect(decideSessionRowText(sessionForToday: nil, verdict: v) == ("Today's session", "Full Upper"))
        #expect(decideSessionRowText(sessionForToday: nil, verdict: verdictParts("GO")) == ("Today's session", "— No data"))
    }
}

/// W-CAL C-4: a night the hub has a VALUE for is never "No data" — while the baseline calibrates the
/// row shows the value with "Calibrating" (and the hub's band once it has one). "No data" = null value.
extension DecideSignalsTests {
    @Test func valueWhileCalibratingShowsTheValueNotNoData() {
        let sig = s("hrv", 27.7, thr: 0, unit: "ms", status: .missing, note: "HRV baseline calibrating — 15 Apple + 13 Garmin nights")
        #expect(decideSignalStatus(sig) == .missing(.calibrating))
        let m = decideSignalRowModel(sig)
        #expect(m.value == 27.7)
        #expect(m.status == .missing(.calibrating))
        #expect(m.status.word == "Calibrating")
        #expect(m.detail == "HRV baseline calibrating — 15 Apple + 13 Garmin nights")
        #expect(decideSignalValueLine(m) == "27.7 ms · calibrating")
    }

    @Test func valueWhileCalibratingWithoutNoteSaysCalibrating() {
        let m = decideSignalRowModel(s("rhr", 60, thr: 0, unit: "bpm", status: .missing))
        #expect(m.status == .missing(.calibrating))
        #expect(m.detail == "your normal — Calibrating")
        #expect(decideSignalValueLine(m) == "60 bpm · calibrating")
    }

    @Test func calibratingValueKeepsTheHubBandWhenServed() {
        var sig = s("hrv", 27.7, thr: 0, unit: "ms", status: .missing)
        sig.bandLo = 25; sig.bandHi = 33
        let m = decideSignalRowModel(sig)
        #expect(m.status == .missing(.calibrating))
        #expect(m.normal == 25...33)
    }

    @Test func nullValueIsStillNoData() {
        let m = decideSignalRowModel(s("hrv", nil, thr: 0, unit: "ms", status: .missing, note: "HRV baseline calibrating — 3/28 Apple nights"))
        #expect(m.status == .missing(.noData))
        #expect(m.detail == "no overnight value yet")
        #expect(decideSignalValueLine(m) == "No data")
    }

    @Test func passingValueLineCarriesTheStatusWord() {
        let m = decideSignalRowModel(s("hrv", 31, thr: 27, unit: "ms", status: .pass))
        #expect(decideSignalValueLine(m) == "31 ms · clear")
    }
}
