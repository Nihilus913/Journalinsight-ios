import Foundation
import Testing
import JICore
@testable import JIFeatures

// W-DATA L2 guard tests — must hold before AND after the lane's rows. Shapes are the live hub's
// 2026-09-27 GETs: `/planning/gate` daily (YAZIO last real day 09-24; 09-25..27 rows null) and
// `/vitals/recovery` (a hub that predates the W-DATA fields).

private func gateRow(_ json: String) throws -> DailyKpiRow {
    try JSON.decoder.decode(DailyKpiRow.self, from: Data(json.utf8))
}

/// R1 (DEV-11): Fuel never implies today — the latest real YAZIO day is named by its own date.
@Test func guardFuelNamesTheYazioDayItShows() throws {
    let rows = try [
        gateRow(#"{"date":"2026-09-27","kcal_consumed":null,"protein_g":null,"steps":5959}"#),
        gateRow(#"{"date":"2026-09-26","kcal_consumed":null,"protein_g":null,"steps":16485}"#),
        gateRow(#"{"date":"2026-09-25","kcal_consumed":null,"protein_g":null,"steps":11082}"#),
        gateRow(#"{"date":"2026-09-24","kcal_consumed":1183.1,"protein_g":98.3,"kcal_goal":1617.2292}"#),
    ]
    // The label is locale-formatted ("Sep 24" / "24 Sep"); pin it to the row's own day.
    let sep24 = kpiAsOfLabel(valueDate: "2026-09-24", today: "2026-09-27")
    #expect(sep24?.contains("24") == true)
    let fuel = dayFuel(daily: rows, today: "2026-09-27")
    #expect(fuel.kcal == 1183.1)
    #expect(fuel.protein == 98.3)
    #expect(fuel.asOf == sep24)
    // The same rows in the hub's other order resolve to the same day.
    #expect(dayFuel(daily: rows.reversed(), today: "2026-09-27").asOf == sep24)
}

/// R1: today's own intake carries no "as of" (nil = today), and no food at all is nil, never 0.
@Test func guardFuelTodayHasNoAsOfAndNoFoodIsNil() throws {
    let today = try gateRow(#"{"date":"2026-09-27","kcal_consumed":640,"protein_g":52}"#)
    #expect(dayFuel(daily: [today], today: "2026-09-27").asOf == nil)
    let empty = try gateRow(#"{"date":"2026-09-27","kcal_consumed":null,"protein_g":null}"#)
    let none = dayFuel(daily: [empty], today: "2026-09-27")
    #expect(none.kcal == nil && none.asOf == nil)
}

/// R4/R6: a hub without the W-DATA recovery fields still decodes (older hubs keep working).
@Test func guardRecoveryDecodesAHubWithoutTheNewFields() throws {
    let json = #"{"date":"2026-09-27","sleep_score":84,"sleep_duration_sec":24814,"deep_sleep_sec":3986,"#
        + #""light_sleep_sec":13156,"rem_sleep_sec":7672,"rhr_bpm":71,"body_battery_avg":null,"body_battery_min":null,"#
        + #""body_battery_max":null,"readiness_score":null,"recovery_time_min":null,"acwr":0.0,"hrv_weekly_avg":39,"hrv_rmssd_ms":23.72}"#
    let day = try JSON.decoder.decode(RecoveryDay.self, from: Data(json.utf8))
    #expect(day.date == "2026-09-27")
    #expect(day.rhrBpm == 71)
    #expect(day.hrvRmssdMs == 23.72)
    #expect(day.sleepDurationSec == 24814)
}

/// R4/R6: a missing sleep fact stays "— not read", never a zero.
@Test func guardMissingSleepFactIsNotRead() {
    #expect(recoverySleepDuration(seconds: nil) == "— not read")
    #expect(recoveryDeepText(hours: nil) == "— not read")
}
