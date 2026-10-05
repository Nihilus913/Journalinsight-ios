import Foundation
import Testing
@testable import JICompute

/// B-90 p4 — Swift MuscleFreshness reproduces HT `tests/fixtures/muscle_freshness.json`
/// (the Python oracle's export) and walks the calibrating 1 / 2 / 3 states.
@Suite struct MuscleFreshnessTests {
    struct ExpRow: Decodable {
        let muscle: String, status: String, workouts: Int, calibration_needed: Int, label: String
        let last_at: String?
        let hours_since: Double?, last_load: Double?, median_load: Double?, p75_load: Double?
        let load_vs_median: Double?, recovery_hours: Double?
    }
    struct Expected: Decodable { let as_of: String; let calibration_workouts: Int; let unknown_muscles: Int; let muscles: [ExpRow] }
    struct W: Decodable { let id: String; let at: String; let loads: [String: Double] }
    struct Case: Decodable { let name: String; let as_of: String; let workouts: [W]; let expected: Expected }
    struct Constants: Decodable { let calibration_workouts: Int; let moderate_hours: Double; let heavy_hours: Double; let fatigued_fraction: Double }
    struct Fixture: Decodable { let constants: Constants; let cases: [Case] }

    static func fixture() throws -> Fixture {
        let url = try #require(Bundle.module.url(forResource: "muscle_freshness", withExtension: "json", subdirectory: "Resources/golden"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    /// ISO datetime; naive = UTC (as the Python oracle).
    static func date(_ s: String) throws -> Date {
        let f = ISO8601DateFormatter()
        return try #require(f.date(from: s) ?? f.date(from: s + "Z"), "bad date \(s)")
    }
    static func iso(_ d: Date?) -> String? { d.map { ISO8601DateFormatter().string(from: $0) } }

    static func close(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (x?, y?): abs(x - y) <= 1e-9 * max(1, abs(y))
        default: false
        }
    }

    static func run(_ c: Case) throws -> MuscleFreshness.Result {
        let ws = try c.workouts.map { MuscleFreshness.Workout(id: $0.id, at: try date($0.at), loads: $0.loads) }
        return MuscleFreshness.compute(workouts: ws, asOf: try date(c.as_of))
    }

    @Test func constantsMatchPython() throws {
        let k = try Self.fixture().constants
        #expect(k.calibration_workouts == MuscleFreshness.calibrationWorkouts)
        #expect(k.moderate_hours == MuscleFreshness.moderateHours)
        #expect(k.heavy_hours == MuscleFreshness.heavyHours)
        #expect(k.fatigued_fraction == MuscleFreshness.fatiguedFraction)
    }

    @Test func everyFixtureCaseMatchesThePythonOracle() throws {
        let f = try Self.fixture()
        #expect(f.cases.count >= 9)
        for c in f.cases {
            let r = try Self.run(c)
            #expect(Self.iso(r.asOf) == c.expected.as_of, "\(c.name) as_of")
            #expect(r.unknownMuscles == c.expected.unknown_muscles, "\(c.name) unknown")
            #expect(r.muscles.map(\.muscle.rawValue) == c.expected.muscles.map(\.muscle), "\(c.name) order")
            for (got, exp) in zip(r.muscles, c.expected.muscles) {
                let tag = "\(c.name)/\(exp.muscle)"
                #expect(got.status.rawValue == exp.status, "\(tag) status")
                #expect(got.workouts == exp.workouts, "\(tag) workouts")
                #expect(got.calibrationNeeded == exp.calibration_needed, "\(tag) calibration")
                #expect(got.label == exp.label, "\(tag) label")
                #expect(Self.iso(got.lastAt) == exp.last_at, "\(tag) last_at")
                #expect(Self.close(got.hoursSince, exp.hours_since), "\(tag) hours")
                #expect(Self.close(got.lastLoad, exp.last_load), "\(tag) last_load")
                #expect(Self.close(got.medianLoad, exp.median_load), "\(tag) median")
                #expect(Self.close(got.p75Load, exp.p75_load), "\(tag) p75")
                #expect(Self.close(got.loadVsMedian, exp.load_vs_median), "\(tag) vs median")
                #expect(Self.close(got.recoveryHours, exp.recovery_hours), "\(tag) window")
            }
        }
    }

    /// The calibrating walk: 0, 1, 2 workouts → not enough data ("n of 3"); the 3rd calibrates.
    @Test func calibratesOnTheThirdWorkout() throws {
        let asOf = try Self.date("2026-10-05T12:00:00Z")
        var ws: [MuscleFreshness.Workout] = []
        #expect(MuscleFreshness.compute(workouts: ws, asOf: asOf).row(.chest)?.workouts == 0)
        for (i, day) in ["2026-09-28T18:00:00Z", "2026-10-01T18:00:00Z", "2026-10-05T00:00:00Z"].enumerated() {
            ws.append(.init(id: "w\(i)", at: try Self.date(day), loads: [Muscle.chest: i == 1 ? 1100.0 : 1000.0]))
            let row = try #require(MuscleFreshness.compute(workouts: ws, asOf: asOf).row(.chest))
            #expect(row.workouts == i + 1)
            if i < 2 {
                #expect(row.status == .notEnoughData)
                #expect(row.recoveryHours == nil)
            } else {
                #expect(row.status == .depleted)  // 12 h after a 48 h-window workout
                #expect(row.recoveryHours == 48)
            }
        }
    }

    @Test func heavyLoadWidensTheWindowTo72h() throws {
        let asOf = try Self.date("2026-10-05T12:00:00Z")
        let base = try ["2026-09-25", "2026-09-27", "2026-09-29"].enumerated().map {
            MuscleFreshness.Workout(id: "b\($0.offset)", at: try Self.date($0.element + "T12:00:00Z"), loads: [Muscle.quads: 1000.0])
        }
        let at = try Self.date("2026-10-02T12:00:00Z")  // 72 h before asOf
        let heavy = MuscleFreshness.compute(workouts: base + [.init(id: "h", at: at, loads: [Muscle.quads: 3000.0])], asOf: asOf.addingTimeInterval(-3600))
        #expect(heavy.row(.quads)?.status == .fatigued)  // 71 h < 72 h
        let moderate = MuscleFreshness.compute(workouts: base + [.init(id: "m", at: at, loads: [Muscle.quads: 1000.0])], asOf: asOf.addingTimeInterval(-3600))
        #expect(moderate.row(.quads)?.status == .recovered)  // 71 h ≥ 48 h
    }

    @Test func quantileMatchesNumpyLinear() {
        #expect(MuscleFreshness.quantile([1], 0.75) == 1)
        #expect(MuscleFreshness.quantile([1, 2, 3, 4], 0.5) == 2.5)
        #expect(MuscleFreshness.quantile([4, 1, 3, 2], 0.75) == 3.25)
    }

    @Test func registeredAsComputed() {
        #expect(ParityRegistry.source(for: "muscle_freshness") == .computed)
        #expect(ParityRegistry.implementation(for: "muscle_freshness") == "JICompute.MuscleFreshness")
    }
}
