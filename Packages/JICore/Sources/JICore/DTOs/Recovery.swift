public struct RecoveryDay: Codable, Sendable, Equatable {
    public var date: String
    public var sleepScore, sleepDurationSec, rhrBpm, bodyBatteryAvg, readinessScore, acwr, hrvWeeklyAvg: Double?
}
public struct RecoveryReport: Codable, Sendable, Equatable { public var days: [RecoveryDay] }
