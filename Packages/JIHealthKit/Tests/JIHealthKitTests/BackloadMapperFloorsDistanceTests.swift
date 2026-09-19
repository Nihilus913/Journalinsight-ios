import Foundation
import Testing
import JIHub
@testable import JIHealthKit

/// W9 L2 (B-30 P5): daily `floors` -> `.flightsClimbed`, daily `distance` -> `.distanceWalkingRunning`
/// (the net-of-workouts figure exactly as sent — never re-subtracted here), both spanning the full
/// local day and carrying the hub `version`.
struct BackloadMapperFloorsDistanceTests {
    @Test func floorsAndDistanceMapToDailyQuantitySpecsWithVersion() {
        let dto = BackloadResponseDTO(
            from: "2026-06-01", to: "2026-06-01", source: "garmin_api",
            sleep: [], rhr: [], steps: [], energy: [], vo2max: [], workouts: [],
            distance: [BackloadDistanceEntryDTO(syncId: "distance:2026-06-01", date: "2026-06-01", meters: 6420.5, version: 1789729180)],
            floors: [BackloadFloorsEntryDTO(syncId: "floors:2026-06-01", date: "2026-06-01", count: 12, version: 1789729180)]
        )
        let specs = BackloadMapper.map(dto)
        let (start, end) = BackloadDateParsing.dayBounds("2026-06-01")!
        #expect(specs.count == 2)
        #expect(specs.contains(.quantity(BackloadQuantitySampleSpec(
            syncId: "floors:2026-06-01", kind: .flightsClimbed, start: start, end: end, value: 12, version: 1789729180))))
        #expect(specs.contains(.quantity(BackloadQuantitySampleSpec(
            syncId: "distance:2026-06-01", kind: .distanceWalkingRunning, start: start, end: end, value: 6420.5, version: 1789729180))))
    }

    @Test func aMalformedDateDropsOnlyThatRow() {
        let dto = BackloadResponseDTO(
            from: "2026-06-01", to: "2026-06-01", source: "garmin_api",
            sleep: [], rhr: [], steps: [], energy: [], vo2max: [], workouts: [],
            distance: [BackloadDistanceEntryDTO(syncId: "distance:x", date: "not-a-date", meters: 1)],
            floors: [BackloadFloorsEntryDTO(syncId: "floors:2026-06-01", date: "2026-06-01", count: 3)]
        )
        let specs = BackloadMapper.map(dto)
        #expect(specs.map(\.syncId) == ["floors:2026-06-01"])
    }
}
