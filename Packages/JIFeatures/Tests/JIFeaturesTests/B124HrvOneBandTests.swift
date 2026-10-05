import Foundation
import Testing
import JICore
import JICompute
import JIDesign
@testable import JIFeatures

/// W-FIX-P1 RG-09 (B-124): "your normal" had four answers — gate 23–27 (28 nights), Recovery card
/// 23–28, HRV detail "Calibrating · 17 of 28 Watch nights", recovery-inputs 22 nights. The hub now
/// serves ONE band (`calibration.hrv`, HT hrv_band.band_from_db); Recovery card and HRV detail read it.
@Suite struct B124HrvOneBandTests {
    /// /vitals/recovery-inputs 2026-10-05 `calibration` from the lane hub (HT fixp1-l3).
    private static let json = """
    {"date":"2026-10-05","days":[],"vitals":false,
     "calibration":{"status":"ok","calibrating":false,"nights":22,"nights_needed":14,
       "components":{"hrv":{"status":"ok","nights":28},"rhr":{"status":"ok","nights":22}},
       "hrv":{"nights":28,"nights_needed":28,"calibrating":false,"n_apple":16,"n_garmin":12,
              "band_lo":23,"band_hi":27,"rolling_7d_ms":22,"status":"amber",
              "band_method":"ln_rmssd_28n_mean_0.5sd"}}}
    """
    /// The gate's HRV row for the same day (/planning/morning).
    private static let gate = GateSignal(key: "hrv", label: "HRV (7-day)", value: 22, unit: "ms", threshold: 23,
                                         direction: .min, status: .amber, bandLo: 23, bandHi: 27)

    private func calibration() throws -> RecoveryCalibration {
        try #require(try JSON.decoder.decode(RecoveryInputsReport.self, from: Data(Self.json.utf8)).calibration)
    }

    @Test func decodesTheHubsHrvBand() throws {
        let hrv = try #require(try calibration().hrv)
        #expect(hrv.nights == 28 && hrv.nightsNeeded == 28 && !hrv.calibrating)
        #expect(hrv.bandLo == 23 && hrv.bandHi == 27 && hrv.rolling7dMs == 22)
    }

    @Test func recoveryCardBandIsTheGatesBand() throws {
        let n = try #require(hrvHubNormal(try calibration()))
        #expect(n.range == Self.gate.hubBand)
        #expect(n.n == 28)
    }

    @Test func hrvDetailShowsTheSameNightsAndBand() throws {
        let cal = try calibration()
        #expect(recoveryCalibrationCaption(cal, key: "hrv") == nil)       // not calibrating: no "17 of 28"
        #expect(kpiHrvHubCaption(cal) == "your normal 23–27 · 28 nights")
        let r = kpiDetailNormal(points: [], today: "2026-10-05", hubCalibrating: false, hubNormal: hrvHubNormal(cal),
                                hubSevenDay: cal.hrv?.rolling7dMs)
        #expect(r.normal?.range == Self.gate.hubBand)
        #expect(r.sevenDay == Self.gate.value)
        #expect(!kpiHrvMixCaption.contains("Watch nights only"))
    }

    @Test func calibratingBandSaysTheHubsCount() throws {
        var cal = try calibration()
        cal.hrv?.calibrating = true
        cal.hrv?.nights = 17
        #expect(recoveryCalibrationCaption(cal, key: "hrv") == "\(JIMissingReason.calibrating.rawValue) · 17 of 28 nights")
        #expect(hrvHubNormal(cal) == nil)
    }
}
