import Foundation
import Testing
import JICore
@testable import JIFeatures

// W-DATA L2 (R4, R6): Recovery "Also watching" and the Deep fact tile read the fields
// `/vitals/recovery` serves (resp_sleep_avg, wrist temp deviation, body battery min/max,
// recovery_time_min, deep_sleep_sec) — dated, and "—" + a reason word when the hub has none.

private let today = "2026-09-27"

private func reading(_ id: String, _ days: [RecoveryDay]) -> RecoveryWatchReading? {
    recoveryWatchReadings(days: days, today: today).first { $0.id == id }
}

@Test func recoveryDayDecodesTheWDataFields() throws {
    let json = #"{"date":"2026-09-27","deep_sleep_sec":3986,"light_sleep_sec":13156,"rem_sleep_sec":7672,"#
        + #""body_battery_min":12,"body_battery_max":88,"recovery_time_min":540,"resp_sleep_avg":17.2,"#
        + #""wrist_temp_c":34.61,"wrist_temp_dev_c":0.34,"wrist_temp_baseline_nights":12}"#
    let d = try JSON.decoder.decode(RecoveryDay.self, from: Data(json.utf8))
    #expect(d.deepSleepSec == 3986 && d.lightSleepSec == 13156 && d.remSleepSec == 7672)
    #expect(d.bodyBatteryMin == 12 && d.bodyBatteryMax == 88)
    #expect(d.recoveryTimeMin == 540)
    #expect(d.respSleepAvg == 17.2)
    #expect(d.wristTempC == 34.61 && d.wristTempDevC == 0.34 && d.wristTempBaselineNights == 12)
    // The offline cache round-trips them (JSON.encoder is snake_case too).
    let back = try JSON.decoder.decode(RecoveryDay.self, from: JSON.encoder.encode(d))
    #expect(back == d)
}

@Test func watchTilesAreLoadThenRespTempBatteryRecoveryTime() {
    #expect(recoveryWatchReadings(days: [], today: today).map(\.id) == ["resp", "wristTemp", "bodyBattery", "recoveryTime"])
}

@Test func nothingServedIsDashNotRead() {
    for r in recoveryWatchReadings(days: [RecoveryDay(date: today)], today: today) {
        #expect(r.value == "—", "\(r.id)")
        #expect(r.caption == "not read", "\(r.id)")
        #expect(r.missing)
    }
}

@Test func respRateIsLastNightsValueDated() {
    var d = RecoveryDay(date: today); d.respSleepAvg = 17.2
    let r = reading("resp", [d])
    #expect(r?.value == "17.2")
    #expect(r?.caption == "br/min · last night")
    // An older night keeps its own date — never passed off as last night.
    var old = RecoveryDay(date: "2026-09-25"); old.respSleepAvg = 16.8
    let o = reading("resp", [old, RecoveryDay(date: today)])
    #expect(o?.value == "16.8")
    #expect(o?.caption == "br/min · " + (kpiAsOfLabel(valueDate: "2026-09-25", today: today) ?? "?"))
}

@Test func wristTempIsTheDeviationFromYourOwnBaselineElseCalibrating() {
    var d = RecoveryDay(date: today); d.wristTempC = 34.61; d.wristTempDevC = 0.34; d.wristTempBaselineNights = 12
    let r = reading("wristTemp", [d])
    #expect(r?.value == "+0.3")
    #expect(r?.caption == "°C vs your normal · last night")
    var cold = d; cold.wristTempDevC = -0.26
    #expect(reading("wristTemp", [cold])?.value == "−0.3")
    // A reading without a baseline yet: never the absolute sensor value, "— Calibrating".
    var cal = RecoveryDay(date: today); cal.wristTempC = 34.61; cal.wristTempBaselineNights = 3
    let c = reading("wristTemp", [cal])
    #expect(c?.value == "—")
    #expect(c?.caption == "Calibrating · 3 of 5 nights")
}

@Test func bodyBatteryAndRecoveryTimeShowWhenCoreHasThem() {
    var d = RecoveryDay(date: "2026-09-26"); d.bodyBatteryMin = 12; d.bodyBatteryMax = 88; d.recoveryTimeMin = 540
    let bb = reading("bodyBattery", [d])
    #expect(bb?.value == "12–88")
    #expect(bb?.caption == "low–high · " + (kpiAsOfLabel(valueDate: "2026-09-26", today: today) ?? "?"))
    let rt = reading("recoveryTime", [d])
    #expect(rt?.value == "9 h")
    var half = d; half.recoveryTimeMin = 90
    #expect(reading("recoveryTime", [half])?.value == "1 h 30")
    // Half a pair is not a range — "— not read", never a made-up other end.
    var one = RecoveryDay(date: today); one.bodyBatteryMax = 88
    #expect(reading("bodyBattery", [one])?.value == "—")
}

@Test func deepFallsBackToTheRoutesDeepSleepForLastNightOnly() {
    let now = ISO8601DateFormatter().date(from: "2026-09-27T10:00:00Z")!
    var d = RecoveryDay(date: "2026-09-27"); d.deepSleepSec = 3986
    #expect(recoveryDeepHours(insightHours: nil, days: [d], now: now) == 3986.0 / 3600)
    // The gate's own deep-sleep reading wins when it has one.
    #expect(recoveryDeepHours(insightHours: 1.2, days: [d], now: now) == 1.2)
    // A stale night is "— not read", not last night's.
    var old = RecoveryDay(date: "2026-09-20"); old.deepSleepSec = 3000
    #expect(recoveryDeepHours(insightHours: nil, days: [old], now: now) == nil)
}
