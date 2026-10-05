import Foundation
import Testing
@testable import JICore

// RG-12 / B-127: the overlay recomputed today's verdict every 15 min and stamped it `now`, so
// "YOUR CALL FOR TODAY · HH:mm", the rows and the word moved during the day. The day's FIRST
// on-device verdict is frozen now — in memory and across relaunches (UserDefaults).
@Suite struct B127FreezeTests {
    static func morning(_ at: String, hrv: Double, sleep: Double, verdict: String) -> OnDeviceMorning {
        OnDeviceMorning(day: "2026-10-05", verdict: verdict, reason: "r", sessionPrescription: nil,
                        gateSignals: [GateSignal(key: "hrv", label: "HRV", value: hrv, unit: "ms", threshold: 23, direction: .min, status: .pass),
                                      GateSignal(key: "sleep_h", label: "Sleep", value: sleep, unit: "h", threshold: 6, direction: .min, status: .pass)],
                        computedAt: at)
    }

    static func freshDefaults() -> UserDefaults {
        let name = "B127FreezeTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func laterComputeNeverRewritesTheFirstVerdict() async {
        let store = UserDefaultsFrozenMorningStore(defaults: Self.freshDefaults())
        let first = await OnDeviceMorningFreeze.resolve(day: "2026-10-05", store: store) {
            Self.morning("2026-10-05T05:08:00Z", hrv: 22, sleep: 7.3, verdict: "MODIFIED")
        }
        #expect(first?.fresh == true)
        let later = await OnDeviceMorningFreeze.resolve(day: "2026-10-05", store: store) {
            Issue.record("a frozen day must not recompute")
            return Self.morning("2026-10-05T13:28:00Z", hrv: 40, sleep: 7.6, verdict: "GO")
        }
        #expect(later?.fresh == false)
        #expect(later?.morning.computedAt == "2026-10-05T05:08:00Z")
        #expect(later?.morning.verdict == "MODIFIED")
        #expect(later?.morning.gateSignals.map(\.value) == [22, 7.3])
    }

    @Test func frozenSurvivesTwoRelaunches() async {
        let defaults = Self.freshDefaults()
        _ = await OnDeviceMorningFreeze.resolve(day: "2026-10-05", store: UserDefaultsFrozenMorningStore(defaults: defaults)) {
            Self.morning("2026-10-05T05:08:00Z", hrv: 22, sleep: 7.3, verdict: "MODIFIED")
        }
        for at in ["2026-10-05T13:28:00Z", "2026-10-05T18:00:00Z"] {   // relaunch = a new store instance
            let r = await OnDeviceMorningFreeze.resolve(day: "2026-10-05", store: UserDefaultsFrozenMorningStore(defaults: defaults)) {
                Self.morning(at, hrv: 40, sleep: 7.6, verdict: "GO")
            }
            #expect(r?.morning.computedAt == "2026-10-05T05:08:00Z")
            #expect(r?.morning.verdict == "MODIFIED")
        }
    }

    @Test func noVerdictYetIsNotFrozen() async {
        let store = UserDefaultsFrozenMorningStore(defaults: Self.freshDefaults())
        let none = await OnDeviceMorningFreeze.resolve(day: "2026-10-05", store: store) { nil }
        #expect(none == nil)
        let then = await OnDeviceMorningFreeze.resolve(day: "2026-10-05", store: store) {
            Self.morning("2026-10-05T06:00:00Z", hrv: 22, sleep: 7.3, verdict: "GO")
        }
        #expect(then?.fresh == true && then?.morning.computedAt == "2026-10-05T06:00:00Z")
    }

    @Test func storeKeepsSevenDays() {
        let store = UserDefaultsFrozenMorningStore(defaults: Self.freshDefaults())
        for d in 1...9 {
            var m = Self.morning("x", hrv: 1, sleep: 1, verdict: "GO"); m.day = String(format: "2026-10-%02d", d)
            store.freeze(m)
        }
        #expect(store.frozen(day: "2026-10-02") == nil)
        #expect(store.frozen(day: "2026-10-03")?.day == "2026-10-03")
        #expect(store.frozen(day: "2026-10-09")?.day == "2026-10-09")
    }
}
