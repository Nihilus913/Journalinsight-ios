import Foundation
import Testing
@testable import JICompute

/// B-57 W3 parity: `recovery.golden.json` from `HealthTraining/scripts/parity/gen_golden_recovery.py`
/// (ground truth `app/vitals/recovery_score.py`). 162 cases: personalNormalCases 72 · recoveryScoreCases 90.
/// Bit-exact: every double (incl. libm `log`/`exp` results), the score and every status compare with `==`.
/// Never edit the fixture by hand; run `HealthTraining/scripts/regen_goldens.py`.

struct PersonalNormalCase: GoldenCase, CustomTestStringConvertible {
    static let allowedKeys: Set<String> = ["series", "today", "expected", "count", "windowMean"]
    struct Expected: Decodable, Sendable { let median, low, high, sd: Double; let n: Int }
    let series: [String: Double?]
    let today: String
    let expected: Expected?
    let count: Int
    let windowMean: Double?
    var clean: [String: Double] { series.compactMapValues { $0 } }
    var testDescription: String { "\(today) n=\(count)" }
}

struct RecoveryScoreCase: GoldenCase, CustomTestStringConvertible {
    static let allowedKeys: Set<String> = ["days", "today", "expected"]
    struct Day: Decodable, Sendable {
        let date: String
        let hrv_ms, rhr_bpm, sleep_h, deep_h, rem_h, load_min: Double?
        var series: RecoverySeriesDay {
            RecoverySeriesDay(date: date, hrvMs: hrv_ms, rhrBpm: rhr_bpm, sleepH: sleep_h, deepH: deep_h, remH: rem_h, loadMin: load_min)
        }
    }
    struct Comp: Decodable, Sendable { let key, status: String; let value, z: Double?; let normalN: Int }
    struct Expected: Decodable, Sendable {
        let status: String; let score: Int?; let raw: Double?; let nights, nightsNeeded: Int; let components: [Comp]
    }
    let days: [Day]
    let today: String
    let expected: Expected
    var testDescription: String { "\(today) days=\(days.count) -> \(expected.status) \(expected.score.map(String.init) ?? "nil")" }
}

enum RecoveryGolden {
    static let normal = GoldenLoader.require(PersonalNormalCase.self, file: "recovery.golden", group: "personalNormalCases")
    static let score = GoldenLoader.require(RecoveryScoreCase.self, file: "recovery.golden", group: "recoveryScoreCases")
}

private func recoveryClose(_ a: Double?, _ b: Double?) -> Bool {
    switch (a, b) {
    case (nil, nil): true
    case let (x?, y?): x == y
    default: false
    }
}

@Test func recoveryGoldenCounts() {
    #expect(RecoveryGolden.normal.count == 72)
    #expect(RecoveryGolden.score.count == 90)
}

@Test(arguments: RecoveryGolden.normal)
func personalNormalMatchesPython(_ c: PersonalNormalCase) throws {
    let got = try PersonalNormal.normal(c.clean, today: c.today)
    #expect(try PersonalNormal.count(c.clean, today: c.today) == c.count)
    #expect(recoveryClose(try PersonalNormal.windowMean(c.clean, today: c.today), c.windowMean))
    if let e = c.expected {
        let g = try #require(got)
        #expect(g.n == e.n)
        #expect(recoveryClose(g.median, e.median) && recoveryClose(g.low, e.low)
                && recoveryClose(g.high, e.high) && recoveryClose(g.sd, e.sd))
        #expect(g.range == g.low...g.high)
    } else {
        #expect(got == nil)
    }
}

@Test(arguments: RecoveryGolden.score)
func recoveryScoreMatchesPython(_ c: RecoveryScoreCase) throws {
    let r = try RecoveryScore.compute(days: c.days.map(\.series), today: c.today)
    #expect(r.status.rawValue == c.expected.status)
    #expect(r.score == c.expected.score)
    #expect(recoveryClose(r.raw, c.expected.raw))
    #expect(r.nights == c.expected.nights && r.nightsNeeded == c.expected.nightsNeeded)
    #expect(r.components.count == c.expected.components.count)
    for (g, e) in zip(r.components, c.expected.components) {
        #expect(g.key.rawValue == e.key && g.status.rawValue == e.status && g.normalN == e.normalN)
        #expect(recoveryClose(g.value, e.value) && recoveryClose(g.z, e.z))
    }
    if let score = r.score { #expect((0...100).contains(score)) }
}

@Test func roundScoreIsHalfUp() {
    #expect(RecoveryScore.roundScore(34.5) == 35)
    #expect(RecoveryScore.roundScore(34.4999) == 34)
    #expect(RecoveryScore.roundScore(0) == 0)
    #expect(RecoveryScore.roundScore(100) == 100)
}

/// Review Focus 3: no HRV last night is "missing", never 50.
@Test func missingHrvTonightIsMissingNotFifty() throws {
    var days: [RecoverySeriesDay] = []
    let today = "2026-09-24"
    for k in stride(from: 40, through: 1, by: -1) {
        let d = try CalendarMath.addDays(today, -k)
        let j = Double(k % 5)
        days.append(RecoverySeriesDay(date: d, hrvMs: 40 + j, rhrBpm: 55 + j, sleepH: 7 + j / 10,
                                      deepH: 1 + j / 20, remH: 1.5 + j / 20, loadMin: 30 + j))
    }
    days.append(RecoverySeriesDay(date: today, rhrBpm: 56, sleepH: 7.2, deepH: 1.1, remH: 1.6))
    let r = try RecoveryScore.compute(days: days, today: today)
    #expect(r.status == .missing)
    #expect(r.score == nil && r.raw == nil)
    #expect(r.component(.hrv)?.status == .noReading)
}

/// The JICompute rule: Recovery sources use no ambient clock/calendar APIs.
@Test func recoverySourcesAvoidAmbientClockAPIs() throws {
    let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/JICompute/Recovery")
    let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
    #expect(files.count == 2)
    for f in files {
        let text = try String(contentsOf: f, encoding: .utf8)
        for banned in ["Date()", "Calendar.current", "TimeZone.current"] {
            #expect(!text.contains(banned), "\(f.lastPathComponent) uses \(banned)")
        }
    }
}
