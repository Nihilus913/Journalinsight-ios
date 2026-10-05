import Testing
import JICore
import JIHealthKit
@testable import JIFeatures

/// W-FIX-P2 RG-16 (B-44od): while the PHONE's HRV baseline calibrates, the gate/Decide HRV row
/// names its source ("phone baseline 2/28") instead of silently disagreeing with the hub's band.
@Suite struct RG16PhoneBaselineRowTests {
    private func hrv(note: String?) -> GateSignal {
        GateSignal(key: "hrv", label: "HRV", value: 26, unit: "ms", threshold: nil, direction: .min,
                   status: .missing, note: note)
    }

    private func result(nights: Int, note: String? = "Calibrating (2/28 nights)") -> OnDeviceVerdictResult {
        OnDeviceVerdictResult(verdict: "GO — A", reason: nil, sessionPrescription: nil,
                              signals: [hrv(note: note)], baselineNights: nights)
    }

    @Test func calibratingPhoneRowDetailNamesThePhoneBaseline() throws {
        let row = try #require(OnDeviceVerdictLabel.sourceLabelled(result(nights: 2)).first)
        let detail = try #require(decideSignalRowModel(row).detail)
        #expect(detail.contains("phone baseline 2/28"))
        #expect(detail.contains("Calibrating (2/28 nights)"))
    }

    @Test func calibratedPhoneRowIsUnchanged() {
        let r = result(nights: 28)
        #expect(OnDeviceVerdictLabel.sourceLabelled(r) == r.signals)
    }

    @Test func noNoteStillCarriesTheSource() throws {
        let row = try #require(OnDeviceVerdictLabel.sourceLabelled(result(nights: 3, note: nil)).first)
        #expect(row.note == "phone baseline 3/28")
    }
}
