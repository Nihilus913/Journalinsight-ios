import Foundation
import Testing
@testable import JICompute

// MARK: - W-B103 V-4 (B-103, Bevel REC-7): vitals (breathing, penalty-only) + temp (display-only)

/// `recovery_vitals.golden.json` from `HealthTraining/scripts/parity/gen_golden_recovery_vitals.py`
/// (ground truth `recovery_score(..., vitals=True)` + `merge_recovery_days`). 70 score cases (each
/// also pins the flag-off result) + 23 merge cases. recovery.golden.json / recovery_merge.golden.json
/// are untouched. Never edit the fixture by hand.
struct RecoveryVitalsDay: Decodable, Sendable {
    let date: String
    let hrv_ms, rhr_bpm, sleep_h, deep_h, rem_h, load_min, resp_bpm, wrist_temp_c: Double?
    var series: RecoverySeriesDay {
        RecoverySeriesDay(date: date, hrvMs: hrv_ms, rhrBpm: rhr_bpm, sleepH: sleep_h, deepH: deep_h, remH: rem_h,
                          loadMin: load_min, respBpm: resp_bpm, wristTempC: wrist_temp_c)
    }
}

struct RecoveryVitalsCase: GoldenCase, CustomTestStringConvertible {
    static let allowedKeys: Set<String> = ["label", "days", "today", "expected", "expectedOff"]
    let label: String
    let days: [RecoveryVitalsDay]
    let today: String
    let expected, expectedOff: RecoveryScoreCase.Expected
    var testDescription: String { "\(label) \(today) -> \(expected.status) \(expected.score.map(String.init) ?? "nil")" }
}

struct RecoveryVitalsMergeCase: GoldenCase, CustomTestStringConvertible {
    static let allowedKeys: Set<String> = ["label", "apple", "garmin", "today", "merged", "expected"]
    let label: String
    let apple, garmin, merged: [RecoveryVitalsDay]
    let today: String
    let expected: RecoveryScoreCase.Expected
    var testDescription: String { "\(label) \(today) -> \(expected.status)" }
}

enum RecoveryVitalsGolden {
    static let score = GoldenLoader.require(RecoveryVitalsCase.self, file: "recovery_vitals.golden", group: "recoveryVitalsCases")
    static let merge = GoldenLoader.require(RecoveryVitalsMergeCase.self, file: "recovery_vitals.golden", group: "recoveryVitalsMergeCases")
}

private func same(_ a: Double?, _ b: Double?) -> Bool {
    switch (a, b) {
    case (nil, nil): true
    case let (x?, y?): x == y
    default: false
    }
}

private func expectMatches(_ r: RecoveryScoreResult, _ e: RecoveryScoreCase.Expected) {
    #expect(r.status.rawValue == e.status)
    #expect(r.score == e.score)
    #expect(same(r.raw, e.raw))
    #expect(r.nights == e.nights && r.nightsNeeded == e.nightsNeeded)
    #expect(r.components.map(\.key.rawValue) == e.components.map(\.key))
    for (g, x) in zip(r.components, e.components) {
        #expect(g.status.rawValue == x.status && g.normalN == x.normalN)
        #expect(same(g.value, x.value) && same(g.z, x.z))
    }
}

@Test func recoveryVitalsGoldenCounts() {
    #expect(RecoveryVitalsGolden.score.count == 70)
    #expect(RecoveryVitalsGolden.merge.count == 23)
}

@Test(arguments: RecoveryVitalsGolden.score)
func recoveryVitalsMatchesPython(_ c: RecoveryVitalsCase) throws {
    let days = c.days.map(\.series)
    expectMatches(try RecoveryScore.compute(days: days, today: c.today, includeVitals: true), c.expected)
    expectMatches(try RecoveryScore.compute(days: days, today: c.today), c.expectedOff)
}

@Test(arguments: RecoveryVitalsGolden.merge)
func recoveryVitalsMergeMatchesPython(_ c: RecoveryVitalsMergeCase) throws {
    let merged = RecoveryScore.mergeRecoveryDays(apple: c.apple.map(\.series), garmin: c.garmin.map(\.series))
    #expect(merged.map(\.date) == c.merged.map(\.date))
    for (g, e) in zip(merged, c.merged) {
        #expect(g.respBpm == e.resp_bpm && g.wristTempC == e.wrist_temp_c && g.hrvMs == e.hrv_ms)
    }
    expectMatches(try RecoveryScore.compute(apple: c.apple.map(\.series), garmin: c.garmin.map(\.series),
                                            today: c.today, includeVitals: true), c.expected)
}

/// Toby 2026-10-04: wrist temp never moves the score; breathing is never a bonus.
@Test func wristTempNeverMovesTheScoreAndLowBreathingIsNoBonus() throws {
    let today = "2026-10-04"
    func hist(resp: Double, temp: Double) throws -> [RecoverySeriesDay] {
        var out: [RecoverySeriesDay] = []
        for k in stride(from: 44, through: 0, by: -1) {
            let j = Double(k % 5)
            out.append(RecoverySeriesDay(date: try CalendarMath.addDays(today, -k), hrvMs: 40 + j, rhrBpm: 55 + j,
                                         sleepH: 7 + j / 10, deepH: 1 + j / 20, remH: 1.5 + j / 20, loadMin: 30 + j,
                                         respBpm: k == 0 ? resp : 17 + j / 10, wristTempC: k == 0 ? temp : 36.5 + j / 10))
        }
        return out
    }
    let hot = try RecoveryScore.compute(days: try hist(resp: 17.2, temp: 40), today: today, includeVitals: true)
    let usual = try RecoveryScore.compute(days: try hist(resp: 17.2, temp: 36.6), today: today, includeVitals: true)
    #expect(hot.raw == usual.raw)
    #expect(hot.component(.temp)?.status == .calibrating && hot.component(.temp)?.z == nil)
    let slow = try RecoveryScore.compute(days: try hist(resp: 14, temp: 36.6), today: today, includeVitals: true)
    #expect(slow.component(.vitals)?.z == 0)
}
