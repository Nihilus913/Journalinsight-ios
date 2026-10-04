import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-B91 S1-4 (Bevel gap BP-11): Decide's "Load" row = ACWR (2 decimals) + the hub's named status
// + its caption. Words: Maintaining / Productive / Overreaching / Paused — never "Overtraining".
struct B91DecideLoadRowTests {
    private func load(_ v: Double?, _ status: String?, note: String = "7 d vs 28 d · 6 sessions in 28 d · 0.80–1.30 is productive") -> GateSignal {
        var s = GateSignal(key: "load", label: "Load", value: v, unit: "", threshold: nil, direction: .max,
                           status: .context, note: note)
        s.loadStatus = status
        return s
    }

    @Test func overreachingRowShowsWordCaptionAndTwoDecimals() {
        let m = decideSignalRowModel(load(1.84, "overreaching"))
        #expect(m.label == "Load")
        #expect(m.status == .overreaching)
        #expect(m.status.word == "Overreaching")
        #expect(m.status.role == .reduced)
        #expect(m.decimals == 2)
        #expect(m.detail == "7 d vs 28 d · 6 sessions in 28 d · 0.80–1.30 is productive")
        #expect(m.normal == nil)
        #expect(decideSignalValueLine(m) == "1.84 · overreaching")
    }

    @Test func eachNamedStatusMaps() {
        #expect(decideSignalRowModel(load(1.07, "productive")).status == .productive)
        #expect(decideSignalRowModel(load(0.62, "maintaining")).status == .maintaining)
        let paused = decideSignalRowModel(load(1.84, "paused", note: "On a break since 28 Sep · set by you · ratio not rated"))
        #expect(paused.status == .paused && paused.status.word == "Paused")
        #expect(paused.detail == "On a break since 28 Sep · set by you · ratio not rated")
        #expect(JISignalStatus.productive.role == .go)
        #expect(JISignalStatus.paused.role == .muted)
        #expect(JISignalStatus.maintaining.role == .muted)
    }

    @Test func unknownOrAbsentStatusStaysContextOnly() {
        #expect(decideSignalRowModel(load(1.2, nil)).status == .contextOnly)
        #expect(decideSignalRowModel(load(1.2, "peaking")).status == .contextOnly)
        #expect(decideSignalRowModel(load(nil, "productive")).status == .missing(.noData))
    }

    /// Toby 2026-10-04: Paused is the user's own status — it holds without an ACWR value too.
    @Test func userPauseHoldsWithoutAValue() {
        let m = decideSignalRowModel(load(nil, "paused", note: "On a break since 1 Oct · set by you · ratio not rated"))
        #expect(m.status == .paused)
        #expect(m.detail?.contains("1 Oct") == true)
    }

    @Test func neverSaysOvertraining() {
        for s in [JISignalStatus.maintaining, .productive, .overreaching, .paused] {
            #expect(!s.word.lowercased().contains("overtrain"))
        }
    }

    @Test func rationaleValueTextHasTwoDecimals() {
        #expect(gateSignalValueText(load(1.837, "overreaching")) == "1.84")
    }
}
