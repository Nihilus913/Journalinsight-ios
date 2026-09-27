import Foundation

/// B-57 W4 — `PUT /api/v1/planning/gate-settings` body. `HubClient.send` encodes with a plain
/// `JSONEncoder()`, so the snake_case wire keys are spelled here. `hr_cap_bpm` and
/// `zone_floors_bpm` are always written, as JSON null when unset (nil cap = no cap; the hub
/// requires the cap key, so a synthesized `encodeIfPresent` would be a 422).
public struct GateSettingsBody: Encodable, Sendable, Equatable {
    public var preset: String
    public var hrCapBpm: Int?
    public var avoidZone5: Bool
    public var zoneFloorsBpm: [Int]?

    public init(preset: String, hrCapBpm: Int?, avoidZone5: Bool, zoneFloorsBpm: [Int]?) {
        self.preset = preset; self.hrCapBpm = hrCapBpm; self.avoidZone5 = avoidZone5; self.zoneFloorsBpm = zoneFloorsBpm
    }

    enum CodingKeys: String, CodingKey {
        case preset, hrCapBpm = "hr_cap_bpm", avoidZone5 = "avoid_zone5", zoneFloorsBpm = "zone_floors_bpm"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(preset, forKey: .preset)
        if let hrCapBpm { try c.encode(hrCapBpm, forKey: .hrCapBpm) } else { try c.encodeNil(forKey: .hrCapBpm) }
        try c.encode(avoidZone5, forKey: .avoidZone5)
        if let zoneFloorsBpm { try c.encode(zoneFloorsBpm, forKey: .zoneFloorsBpm) } else { try c.encodeNil(forKey: .zoneFloorsBpm) }
    }
}

/// The hub's answer. Decoded with `JSON.decoder` (`.convertFromSnakeCase`), so NO CodingKeys:
/// an explicit "hr_cap_bpm" raw value would never match after the key conversion.
public struct GateSettingsDTO: Decodable, Sendable, Equatable {
    public var preset: String
    public var hrCapBpm: Int?
    public var avoidZone5: Bool
    public var zoneFloorsBpm: [Int]?
    public var hrvLowNights: Int
    public var updatedAt: String?

    public init(preset: String, hrCapBpm: Int?, avoidZone5: Bool, zoneFloorsBpm: [Int]?, hrvLowNights: Int, updatedAt: String?) {
        self.preset = preset; self.hrCapBpm = hrCapBpm; self.avoidZone5 = avoidZone5; self.zoneFloorsBpm = zoneFloorsBpm
        self.hrvLowNights = hrvLowNights; self.updatedAt = updatedAt
    }
}
