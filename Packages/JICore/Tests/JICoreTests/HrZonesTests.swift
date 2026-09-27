import Testing
@testable import JICore

/// B-57 W4 (Toby 2026-09-24): zones are the user's. The model is the threshold-anchored scheme
/// in HT docs/research/hr-zone-anchoring.md; Toby's AWU3 zones are its max-HR column exactly.
@Test func maxHrModelReproducesTheResearchTable() {
    let z = HrZones.derived(anchor: .maxHr, bpm: 198)
    #expect(z.floorsBpm == [97, 117, 139, 160, 176])
    #expect(z == HrZones.legacyPreW4)
    #expect(z.rangeText(1) == "97–116" && z.rangeText(2) == "117–138" && z.rangeText(4) == "160–175")
    #expect(z.rangeText(5) == "176–198")
}

@Test func lthrModelUsesTheLthrColumn() {
    let z = HrZones.derived(anchor: .lthr, bpm: 170)
    #expect(z.floorsBpm == [97, 117, 139, 160, 175])
    #expect(z.rangeText(5) == "175+")          // no known max: open-ended
    #expect(HrZones.derived(anchor: .maxHr, bpm: 180).floorsBpm == [88, 106, 126, 146, 160])
}

@Test func zoneLookupAndZone5Floor() {
    let z = HrZones.legacyPreW4
    #expect(z.zone(forBpm: 90) == 0)
    #expect(z.zone(forBpm: 117) == 2)
    #expect(z.zone(forBpm: 175) == 4)
    #expect(z.zone(forBpm: 176) == 5)
    #expect(z.zone5FloorBpm == 176)
}

@Test func everyBoundaryIsEditableButStaysAscending() throws {
    let z = HrZones.legacyPreW4
    let edited = try #require(z.editing(zone: 5, floorBpm: 180))
    #expect(edited.floorsBpm == [97, 117, 139, 160, 180] && edited.zone5FloorBpm == 180)
    #expect(z.editing(zone: 3, floorBpm: 117) == nil)   // would equal Z2's floor
    #expect(z.editing(zone: 1, floorBpm: 0) == nil)
    #expect(z.editing(zone: 6, floorBpm: 200) == nil)
    #expect(!HrZones(anchor: .maxHr, anchorBpm: 190, floorsBpm: [100, 120]).isValid)
    #expect(HrZones(anchor: .maxHr, anchorBpm: 190, floorsBpm: [100, 120]).zone5FloorBpm == nil)
    #expect(HrZones(anchor: .maxHr, anchorBpm: 190, floorsBpm: [100, 120]).rangeText(1) == "—")
}

@Test func noLimitsIsTheDefault() {
    #expect(WorkoutHrLimits() == .none)
    #expect(WorkoutHrLimits.none.capBpm == nil && WorkoutHrLimits.none.zone5FloorBpm == nil)
}
