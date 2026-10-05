import Foundation
import Testing
@testable import JICore

// W-B91 S1-4: the hub's Decide "Load" row carries `load_status` (HT app/vitals/load_status.py).
// Payload = the live E2E record (ht_b91_main, verdict 2026-10-04, hub :8303).
@Test func gateSignalDecodesLoadStatus() throws {
    let json = Data(#"""
    {"key":"load","label":"Load","value":1.84,"unit":"","threshold":null,"direction":"max",
     "scale_min":0,"scale_max":2.5,"status":"context",
     "note":"7 d vs 28 d · 6 sessions in 28 d · 0.80–1.30 is productive",
     "band_lo":null,"band_hi":null,"band_method":null,"load_status":"overreaching",
     "sessions_28d":6,"break_days":null,"as_of":"2026-10-03"}
    """#.utf8)
    let s = try JSON.decoder.decode(GateSignal.self, from: json)
    #expect(s.key == "load" && s.value == 1.84)
    #expect(s.loadStatus == "overreaching")
    #expect(s.status == .context)
}

@Test func gateSignalWithoutLoadStatusDecodesNil() throws {
    let old = Data(#"{"key":"rhr","label":"RHR","value":55,"unit":"bpm","threshold":65,"direction":"max","scale_min":40,"scale_max":80,"status":"pass"}"#.utf8)
    #expect(try JSON.decoder.decode(GateSignal.self, from: old).loadStatus == nil)
}

// W-B91 S3 b91p2: the load row's acute / chronic daily load (Strain sheet tiles).
@Test func gateSignalDecodesAcuteAndChronicLoad() throws {
    let json = Data(#"{"key":"load","label":"Load","value":1.84,"unit":"","threshold":null,"direction":"max","scale_min":0,"scale_max":2.5,"status":"context","note":"x","load_status":"overreaching","acute_load":1.21,"chronic_load":0.66}"#.utf8)
    let s = try JSON.decoder.decode(GateSignal.self, from: json)
    #expect(s.acuteLoad == 1.21 && s.chronicLoad == 0.66)
    let old = Data(#"{"key":"rhr","label":"RHR","value":55,"unit":"bpm","threshold":65,"direction":"max","scale_min":40,"scale_max":80,"status":"pass"}"#.utf8)
    let o = try JSON.decoder.decode(GateSignal.self, from: old)
    #expect(o.acuteLoad == nil && o.chronicLoad == nil)
}
