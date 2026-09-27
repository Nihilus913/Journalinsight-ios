import Foundation

/// B-57 W4 (Toby 2026-09-24): heart-rate zones are the USER's, never app constants.
/// Five zone floors (Z1…Z5 lower bounds, bpm) derived from the user's max HR or LTHR with the
/// threshold-anchored model in HT `docs/research/hr-zone-anchoring.md`: floors at
/// 49 / 59 / 70 / 81 / 89 % of max HR, or 57 / 69 / 82 / 94 / 103 % of LTHR. Every floor is
/// editable afterwards (`editing(zone:floorBpm:)`).
public nonisolated enum HrZoneAnchor: String, Codable, CaseIterable, Sendable {
    case maxHr, lthr

    public var title: String {
        switch self { case .maxHr: "Max heart rate"; case .lthr: "Lactate threshold HR" }
    }
}

public nonisolated struct HrZones: Codable, Equatable, Sendable {
    public static let maxHrPercents = [49, 59, 70, 81, 89]
    public static let lthrPercents = [57, 69, 82, 94, 103]
    /// Toby's pre-W4 zones (AWU3 manual zones, max HR 198). Migration only, never a default.
    public static let legacyPreW4 = HrZones(anchor: .maxHr, anchorBpm: 198, floorsBpm: [97, 117, 139, 160, 176])

    public var anchor: HrZoneAnchor
    public var anchorBpm: Int
    /// Z1…Z5 lower bounds in bpm, strictly ascending.
    public var floorsBpm: [Int]

    public init(anchor: HrZoneAnchor, anchorBpm: Int, floorsBpm: [Int]) {
        self.anchor = anchor; self.anchorBpm = anchorBpm; self.floorsBpm = floorsBpm
    }

    public static func derived(anchor: HrZoneAnchor, bpm: Int) -> HrZones {
        let percents = anchor == .maxHr ? maxHrPercents : lthrPercents
        return HrZones(anchor: anchor, anchorBpm: bpm,
                       floorsBpm: percents.map { Int((Double(bpm * $0) / 100).rounded(.toNearestOrAwayFromZero)) })
    }

    public var isValid: Bool {
        floorsBpm.count == 5 && floorsBpm.allSatisfy { $0 > 0 } && zip(floorsBpm, floorsBpm.dropFirst()).allSatisfy { $0 < $1 }
    }

    public var zone5FloorBpm: Int? { isValid ? floorsBpm[4] : nil }

    /// 0 = below Z1, else 1…5.
    public func zone(forBpm bpm: Int) -> Int { floorsBpm.filter { $0 <= bpm }.count }

    /// "117–138"; Z5 ends at max HR when that is the anchor, else it is open-ended ("175+").
    /// Invalid zones or an out-of-range zone number = "—" (never a made-up range).
    public func rangeText(_ zone: Int) -> String {
        guard isValid, (1...5).contains(zone) else { return "—" }
        let lo = floorsBpm[zone - 1]
        if zone < 5 { return "\(lo)–\(floorsBpm[zone] - 1)" }
        return anchor == .maxHr ? "\(lo)–\(anchorBpm)" : "\(lo)+"
    }

    /// The same zones with one floor changed, or nil when that breaks the ascending order.
    public func editing(zone: Int, floorBpm: Int) -> HrZones? {
        guard (1...5).contains(zone), floorsBpm.count == 5 else { return nil }
        var next = self
        next.floorsBpm[zone - 1] = floorBpm
        return next.isValid ? next : nil
    }
}

/// What the Watch builder must respect: the user's cap and, if they chose to avoid it, the
/// floor of their Zone 5. `.none` = no limits (Toby 2026-09-24: both are optional).
public nonisolated struct WorkoutHrLimits: Equatable, Sendable {
    public var capBpm: Int?
    public var zone5FloorBpm: Int?
    public init(capBpm: Int? = nil, zone5FloorBpm: Int? = nil) { self.capBpm = capBpm; self.zone5FloorBpm = zone5FloorBpm }
    public static let none = WorkoutHrLimits()
}
