import Foundation

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
