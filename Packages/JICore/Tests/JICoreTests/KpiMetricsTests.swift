import Foundation
import Testing
@testable import JICore

@Test func everyKpiMetricIdHasExactlyOneDef() {
    for id in KpiMetricId.allCases {
        #expect(KpiMetrics.all.filter { $0.id == id }.count == 1)
    }
    #expect(KpiMetrics.all.count == KpiMetricId.allCases.count)
}

/// `RecoveryDay`/`NutritionDailyRow`/`GateAverages` have no public memberwise init accessible
/// cross-module (their auto-synthesized memberwise init is internal) — decode them from a JSON
/// literal instead, same as every other JICore DTO test does.
private func decodeJSON<T: Decodable>(_ json: String, as type: T.Type) -> T {
    try! JSON.decoder.decode(T.self, from: Data(json.utf8))
}

@Test func recoverySourcedValueUsesLatestDayByDate() {
    let days: [RecoveryDay] = [
        decodeJSON(#"{"date":"2026-09-10","rhr_bpm":40,"hrv_weekly_avg":40}"#, as: RecoveryDay.self),
        decodeJSON(#"{"date":"2026-09-12","rhr_bpm":45,"hrv_weekly_avg":45}"#, as: RecoveryDay.self),
    ]
    let value = KpiMetrics.value(for: .rhr, recovery: days, nutrition: [], dailyRows: [], gateAverages: nil)
    #expect(value == 45)
    // W-FIX1 BUG-06: `hrv_weekly_avg` is the hub's 7-day Garmin/Apple mix, never shown as HRV.
    #expect(KpiMetrics.value(for: .hrv, recovery: days, nutrition: [], dailyRows: [], gateAverages: nil) == nil)
}

@Test func nutritionSourcedValueUsesLatestDay() {
    let days: [NutritionDailyRow] = [
        decodeJSON(#"{"date":"2026-09-10","kcal_consumed":1800}"#, as: NutritionDailyRow.self),
        decodeJSON(#"{"date":"2026-09-12","kcal_consumed":2000}"#, as: NutritionDailyRow.self),
    ]
    #expect(KpiMetrics.value(for: .kcal, recovery: [], nutrition: days, dailyRows: [], gateAverages: nil) == 2000)
}

@Test func weightFallsBackToGateAveragesWhenNoDailyRowHasIt() {
    let averages: GateAverages = decodeJSON(#"{"avg_weight_kg":79.1,"trends":{}}"#, as: GateAverages.self)
    let value = KpiMetrics.value(for: .weight, recovery: [], nutrition: [], dailyRows: [], gateAverages: averages)
    #expect(value == 79.1)
}

@Test func missingValueNeverRendersAsZero() {
    #expect(formatKpiValue(nil, decimals: 0) == "—")
    #expect(formatKpiValue(0, decimals: 0) == "0") // a genuine 0 is a real value — only nil is masked
}

@Test func targetTextJoinsMultipleMatchingRules() {
    let targets = [
        KpiTarget(targetId: 6, metric: "acwr", operator: ">", threshold: 1.3),
        KpiTarget(targetId: 10, metric: "acwr", operator: "<", threshold: 0.8),
    ]
    let text = KpiMetrics.targetText(for: .acwr, targets: targets)
    #expect(text == "> 1.3; < 0.8")
}

@Test func targetTextFormatsBetweenAsRange() {
    let targets = [KpiTarget(targetId: 11, metric: "acwr", operator: "between", threshold: 0.8, thresholdHi: 1.3)]
    #expect(KpiMetrics.targetText(for: .acwr, targets: targets) == "0.8–1.3")
}

@Test func targetTextNilWhenMetricHasNoRule() {
    #expect(KpiMetrics.targetText(for: .rhr, targets: [KpiTarget(targetId: 1, metric: "acwr", operator: ">", threshold: 1.3)]) == nil)
}

// MARK: - W-KEYS D1r: one KPI descriptor (label, short label, icon) + one alias map

/// Every wire id and every display label the screens pass around lands on one `KpiMetricId` —
/// the aliases `JIDesign/MetricTint.swift` used to keep on its own.
@Test(arguments: [
    ("hrv", KpiMetricId.hrv), ("HRV", .hrv),
    ("rhr", .rhr), ("restinghr", .rhr), ("resting_hr", .rhr), ("Resting HR", .rhr),
    ("sleep", .sleep), ("sleepscore", .sleep), ("sleep_score", .sleep), ("Sleep score", .sleep), ("SLEEP SCORE", .sleep),
    ("acwr", .acwr), ("load", .acwr), ("trainingload", .acwr), ("training_load", .acwr), ("Load (ACWR)", .acwr),
    ("kcal", .kcal), ("calories", .kcal), ("Calories", .kcal),
    ("carbs", .carbs), ("carbohydrates", .carbs), ("Carbohydrates", .carbs),
    ("body_battery", .bodyBattery), ("  Steps ", .steps), ("protein", .protein), ("fat", .fat),
    ("weight", .weight), ("readiness", .readiness),
])
func everyAliasNormalizes(alias: String, id: KpiMetricId) {
    #expect(KpiMetricId(normalizing: alias) == id)
}

@Test func everyRawValueNormalizesToItself() {
    for id in KpiMetricId.allCases { #expect(KpiMetricId(normalizing: id.rawValue) == id) }
}

@Test(arguments: ["", "fibre", "sugar", "not_a_metric", "zzz"])
func unknownIdsDoNotNormalize(alias: String) {
    #expect(KpiMetricId(normalizing: alias) == nil)
}

@Test func everyMetricHasAShortLabelAndASymbol() {
    for id in KpiMetricId.allCases {
        #expect(!KpiMetrics.def(id).symbol.isEmpty, Comment(rawValue: id.rawValue))
        #expect(!KpiMetrics.def(id).shortLabel.isEmpty, Comment(rawValue: id.rawValue))
    }
}

/// Toby D2 (2026-10-03): one icon per metric, and the set he named.
@Test func theDescriptorCarriesTobysIconSet() {
    #expect(KpiMetrics.def(.sleep).symbol == "moon")
    #expect(KpiMetrics.def(.readiness).symbol == "gauge.medium")
    #expect(KpiMetrics.def(.acwr).symbol == "bolt")
    #expect(KpiMetrics.def(.rhr).symbol == "heart")
    #expect(KpiMetrics.def(.carbs).symbol == "leaf")
    #expect(KpiMetrics.def(.fat).symbol == "drop")
    #expect(Set(KpiMetricId.allCases.map { KpiMetrics.def($0).symbol }).count == KpiMetricId.allCases.count)
}
