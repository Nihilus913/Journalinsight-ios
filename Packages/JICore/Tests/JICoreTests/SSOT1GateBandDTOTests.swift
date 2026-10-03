import Foundation
import Testing
@testable import JICore

// W-SSOT-1 SS-4 (XC half): `GateSignalOut` carries the hub's band as data — `band_lo`, `band_hi`,
// `band_method` — so the app no longer parses "band 41–52 ms" out of the note.
@Test func gateSignalDecodesTheHubBandFields() throws {
    let json = Data(#"""
    {"key":"hrv","label":"HRV (7-day)","value":46,"unit":"ms","threshold":41,"direction":"min",
     "scale_min":0,"scale_max":80,"status":"pass","note":"band 41–52 ms",
     "band_lo":41.0,"band_hi":52.0,"band_method":"apple_7d"}
    """#.utf8)
    let s = try JSON.decoder.decode(GateSignal.self, from: json)
    #expect(s.bandLo == 41 && s.bandHi == 52)
    #expect(s.bandMethod == "apple_7d")
    #expect(s.hubBand == 41...52)
}

@Test func gateSignalWithoutBandFieldsDecodesNilBand() throws {
    let json = Data(#"""
    {"key":"rhr","label":"RHR","value":55,"unit":"bpm","threshold":65,"direction":"max",
     "scale_min":40,"scale_max":80,"status":"pass","note":null,"band_lo":null,"band_hi":null,"band_method":null}
    """#.utf8)
    let s = try JSON.decoder.decode(GateSignal.self, from: json)
    #expect(s.bandLo == nil && s.bandHi == nil && s.bandMethod == nil)
    #expect(s.hubBand == nil)
    let old = Data(#"{"key":"rhr","label":"RHR","value":55,"unit":"bpm","threshold":65,"direction":"max","scale_min":40,"scale_max":80,"status":"pass"}"#.utf8)
    #expect(try JSON.decoder.decode(GateSignal.self, from: old).hubBand == nil)
}

@Test func anInvertedHubBandIsNoBand() {
    var s = GateSignal(key: "hrv", label: "HRV", value: 40, unit: "ms", threshold: 30, direction: .min,
                       status: .pass)
    s.bandLo = 52; s.bandHi = 41
    #expect(s.hubBand == nil)
}

@Test func gateSignalBandGoldenDecodes() throws {
    // HT `tests/fixtures/ssot1/gate_signals_band.json` (L1, 4f8bd19): extra keys (nights, …) are ignored.
    let url = try #require(Bundle.module.url(forResource: "gate_signals_band", withExtension: "json", subdirectory: "Resources/ssot1"))
    let s = try JSON.decoder.decode([GateSignal].self, from: Data(contentsOf: url))
    #expect(s.map(\.key) == ["hrv", "sleep_h", "hrv_day"])
    #expect(s[0].hubBand == 41...52 && s[0].bandMethod == "ln_rmssd_28n_mean_0.5sd")
    #expect(s[1].hubBand == nil && s[1].bandMethod == nil)
    #expect(s[2].hubBand == nil)
}
