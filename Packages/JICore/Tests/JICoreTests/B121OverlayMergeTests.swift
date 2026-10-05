import Foundation
import Testing
@testable import JICore

// RG-05 / B-121: the on-device overlay replaced the whole `gate_signals` array, so hub-only rows
// (Load / ACWR, "Paused · since …") vanished from Decide in Release. The merge is per key now.
@Suite struct B121OverlayMergeTests {
    static func signal(_ key: String, _ value: Double?, status: GateSignalStatus = .pass, note: String? = nil) -> GateSignal {
        GateSignal(key: key, label: key, value: value, unit: "", threshold: nil, direction: .min, status: status, note: note)
    }

    static func hubMorning() throws -> MorningResponse {
        var m = try JSON.decoder.decode(MorningResponse.self, from: Data(#"{"carb_watch_floor":150}"#.utf8))
        var load = signal("load", 1.84, status: .context, note: "Paused · since 2026-09-30")
        load.loadStatus = "paused"
        m.gateSignals = [signal("hrv", 22), signal("sleep_h", 7.3), load]
        m.verdict = "GO"
        return m
    }

    @Test func hubOnlyLoadRowSurvivesOverlay() throws {
        let phone = OnDeviceMorning(day: "2026-10-05", verdict: "MODIFIED", reason: "r", sessionPrescription: nil,
                                    gateSignals: [Self.signal("hrv", 40), Self.signal("sleep_h", 7.6), Self.signal("rhr", 55)],
                                    computedAt: "2026-10-05T05:08:00Z")
        let r = try Self.hubMorning().overlaid(with: phone)
        let keys = (r.gateSignals ?? []).map(\.key)
        #expect(keys == ["hrv", "sleep_h", "load", "rhr"])
        let load = try #require(r.gateSignals?.first { $0.key == "load" })
        #expect(load.value == 1.84 && load.loadStatus == "paused")
        #expect(load.note == "Paused · since 2026-09-30")
        // phone rows replace only the keys it computes
        #expect(r.gateSignals?.first { $0.key == "hrv" }?.value == 40)
        #expect(r.gateSignals?.first { $0.key == "sleep_h" }?.value == 7.6)
        #expect(r.verdict == "MODIFIED")
    }

    @Test func noHubSignalsTakesPhoneRows() throws {
        var hub = try Self.hubMorning(); hub.gateSignals = nil
        let phone = OnDeviceMorning(day: "2026-10-05", verdict: "GO", reason: nil, sessionPrescription: nil,
                                    gateSignals: [Self.signal("hrv", 40)], computedAt: "x")
        #expect(hub.overlaid(with: phone).gateSignals?.map(\.key) == ["hrv"])
    }
}
