import Testing
import JIPersistence
@testable import JIFeatures

/// W-ONDEVICE O-10: the Developer screen's dual-run line.
@Test func parityLineCountsDaysAndDiffs() {
    #expect(onDeviceParityLine(ShadowParity(days: 3, diffs: 1, hubMissing: 0)) == "parity 3 days, 1 diff")
    #expect(onDeviceParityLine(ShadowParity(days: 1, diffs: 0, hubMissing: 2)) == "parity 1 day, 0 diffs · 2 without hub")
}

@Test func shadowRowLineShowsClassesAndLatency() {
    let row = ShadowVerdictRow(day: "2026-10-04", onDeviceVerdict: "GO — A", hubVerdict: nil, inputsDigest: "x",
                               computedAt: "2026-10-04T03:20:00Z", latencyFromWakeSec: 754)
    #expect(onDeviceShadowRowLine(row) == "2026-10-04 · GO vs hub — · 13 min after wake")
}
