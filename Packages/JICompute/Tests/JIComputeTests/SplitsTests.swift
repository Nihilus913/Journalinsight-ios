import Foundation
import Testing
@testable import JICompute

/// W-B98A B98-3: Swift port of HT `app/training/splits.py` `km_splits`. Fixtures under
/// Resources/splits are byte copies of HT `tests/fixtures/splits/` (b98p1); never edit here.
@Suite struct SplitsTests {
    static let runId = "23926763203"
    static let treadmillId = "24191727351"
    static let runGolden: [Double] = [841, 777, 751, 690, 656, 605, 482]
    static let garminLaps: [Double] = [836, 778, 749, 683, 662, 606, 478]

    struct Expected: Decodable {
        let km: Int
        let distance_m: Double
        let duration_s: Double
        let pace_s_per_km: Double?
        let mean_hr: Double?
        let elevation_gain_m: Double?
    }

    private struct Fixture: Decodable {
        let columns: [String]
        let samples: [[Double?]]
    }

    static func url(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources/splits"))
    }

    static func samples(_ id: String) throws -> [Splits.Sample] {
        let f = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url(id)))
        #expect(f.columns == ["t", "hr", "lat", "lon", "elevation_m", "speed_mps"])
        return f.samples.map { r in
            Splits.Sample(t: r[0]!, hr: r[1], lat: r[2], lon: r[3], elevationM: r[4], speedMps: r[5])
        }
    }

    static func expected(_ id: String) throws -> [Expected] {
        try JSONDecoder().decode([Expected].self, from: Data(contentsOf: url("\(id)_expected")))
    }

    static func steady(_ n: Int, speed: Double = 2.5, t0: Double = 0, hr: Double = 140) -> [Splits.Sample] {
        (0..<n).map { Splits.Sample(t: t0 + Double($0), hr: hr, lat: nil, lon: nil, elevationM: nil, speedMps: speed) }
    }

    @Test func garminRunSevenBucketsGolden() throws {
        let sp = Splits.kmSplits(try Self.samples(Self.runId))
        #expect(sp.count == 7)
        for (got, want) in zip(sp, Self.runGolden) { #expect(abs(got.durationS - want) <= 1) }
        #expect(sp.map(\.km) == [1, 2, 3, 4, 5, 6, 7])
        for s in sp.prefix(6) { #expect(abs(s.distanceM - 1000) <= 0.01) }
        #expect(sp[6].distanceM > 600 && sp[6].distanceM < 750)
        for (got, garmin) in zip(sp, Self.garminLaps) { #expect(abs(got.durationS - garmin) <= 8) }
        #expect(sp.allSatisfy { ($0.elevationGainM ?? -1) >= 0 })
    }

    @Test(arguments: [runId, treadmillId])
    func matchesSharedGoldenFiles(id: String) throws {
        let got = Splits.kmSplits(try Self.samples(id))
        let want = try Self.expected(id)
        #expect(got.count == want.count)
        for (g, w) in zip(got, want) {
            #expect(g.km == w.km)
            #expect(g.distanceM == w.distance_m, "km \(w.km) distance")
            #expect(g.durationS == w.duration_s, "km \(w.km) duration")
            #expect(g.paceSPerKm == w.pace_s_per_km, "km \(w.km) pace")
            #expect(g.meanHr == w.mean_hr, "km \(w.km) hr")
            #expect(g.elevationGainM == w.elevation_gain_m, "km \(w.km) elevation")
        }
    }

    @Test func treadmillSpeedNoGps() throws {
        let s = try Self.samples(Self.treadmillId)
        #expect(s.allSatisfy { $0.lat == nil })
        let sp = Splits.kmSplits(s)
        #expect(sp.map { $0.durationS.rounded() } == [631, 475, 448, 433, 520])
        #expect(abs(sp.last!.distanceM - 913) <= 2)
        #expect(sp.allSatisfy { $0.elevationGainM == nil })
    }

    @Test func pauseGapIsCapped() {
        let sp = Splits.kmSplits(Self.steady(401) + Self.steady(401, t0: 401 + 1800))
        #expect(sp.count == 2)
        #expect(abs(sp[0].durationS - 400) <= 0.5)
        #expect(sp[1].durationS <= 400 + Splits.maxSampleGapSec + 0.5)
    }

    @Test func interpolatedCrossing() {
        let sp = Splits.kmSplits(Self.steady(1001, speed: 3.0))
        #expect(sp.map(\.durationS) == [333.33, 333.33, 333.33])
        #expect(abs((sp[0].paceSPerKm ?? 0) - 333.33) <= 0.01)
        #expect(sp[0].meanHr == 140)
    }

    @Test func noSpeedNoGpsIsEmpty() {
        let s = (0..<600).map { Splits.Sample(t: Double($0), hr: 120, lat: nil, lon: nil, elevationM: nil, speedMps: nil) }
        #expect(Splits.kmSplits(s).isEmpty)
        #expect(Splits.kmSplits([]).isEmpty)
    }

    @Test func gpsOnlyUsesHaversine() {
        let s = (0..<200).map {
            Splits.Sample(t: Double($0), hr: 130, lat: 47.0 + Double($0) * 0.0001, lon: 8.5, elevationM: 400, speedMps: nil)
        }
        let sp = Splits.kmSplits(s)
        #expect(sp.count == 3)
        #expect(abs(sp[0].durationS - 1000 / 11.1195) <= 0.5)
    }

    @Test func acceptsDates() {
        let t0 = Date(timeIntervalSince1970: 1_786_381_200)
        let s = Self.steady(401).map {
            Splits.Sample(at: t0.addingTimeInterval($0.t), hr: $0.hr, lat: nil, lon: nil, elevationM: nil, speedMps: $0.speedMps)
        }
        #expect(abs(Splits.kmSplits(s)[0].durationS - 400) <= 0.5)
    }

    @Test func registryEntryIsComputed() {
        #expect(ParityRegistry.source(for: Splits.registryKey) == .computed)
        #expect(ParityRegistry.implementation(for: Splits.registryKey) == "JICompute.Splits")
        #expect(ParityRegistry.entry(for: Splits.registryKey).notes.contains("B-98"))
    }
}
