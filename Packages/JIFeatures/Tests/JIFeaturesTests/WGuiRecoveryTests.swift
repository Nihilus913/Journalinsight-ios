import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-GUI R1 — Recovery (mockup 03): cards, nights, honest "your normal —", fact tiles.
private func day(_ date: String, hrv: Double? = nil, rhr: Double? = nil, sleep: Double? = nil, secs: Double? = nil) -> RecoveryDay {
    var d = RecoveryDay(date: date)
    d.hrvRmssdMs = hrv; d.rhrBpm = rhr; d.sleepScore = sleep; d.sleepDurationSec = secs
    return d
}

@Test func cardsAreHrvRhrSleepWithTheirOwnColours() {
    #expect(RecoveryCardMetric.allCases.map(\.title) == ["Overnight HRV", "Resting HR", "Sleep"])
    #expect(RecoveryCardMetric.hrv.tint == .hrv && RecoveryCardMetric.rhr.tint == .rhr && RecoveryCardMetric.sleep.tint == .sleep)
    #expect(RecoveryCardMetric.hrv.unit == "ms RMSSD")
}

@Test func nightsPerMetricKeepMissingNightsMissing() {
    let days = [day("2026-09-24", hrv: 29, rhr: 52), day("2026-09-25", rhr: 54), day("2026-09-26", hrv: 25, rhr: nil, sleep: 81)]
    let rhr = recoveryNights(days: days, metric: .rhr)
    #expect(rhr.map(\.value) == [52, 54, nil])
    #expect(rhr.last?.isLatest == true)
    #expect(recoveryNights(days: days, metric: .sleep).map(\.value) == [nil, nil, 81])
    #expect(recoveryHrvNights(days: days).map(\.value) == [29, nil, 25])
}

@Test func normalLineAndFactTilesAreHonest() {
    #expect(recoveryNormalText(nil) == "your normal —")
    #expect(recoveryNormalText(27...30) == "your normal 27–30")
    #expect(recoverySleepDuration(seconds: 26_640) == "7 h 24")
    #expect(recoverySleepDuration(seconds: nil) == "— not read")
    #expect(recoverySubtitle(nights: 14) == "How you are trending · 14 nights")
    #expect(recoverySubtitle(nights: 1) == "How you are trending · 1 night")
    #expect(recoveryMonitorCaption.hasPrefix("Trends only."))
}
