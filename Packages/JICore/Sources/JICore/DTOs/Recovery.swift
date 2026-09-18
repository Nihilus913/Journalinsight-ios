public struct RecoveryDay: Codable, Sendable, Equatable {
    public var date: String
    public var sleepScore, sleepDurationSec, rhrBpm, bodyBatteryAvg, readinessScore, acwr, hrvWeeklyAvg: Double?

    /// W7-L3: the synthesized memberwise initializer is `internal`, so until now a `RecoveryDay`
    /// could only ever be *decoded*. The on-device T2 provider (`JIHealthKit.HealthKitProvider`)
    /// assembles days from HealthKit samples instead of a hub response and needs to build one
    /// across module boundaries. Purely additive — every existing decode path is unchanged.
    public init(
        date: String,
        sleepScore: Double? = nil,
        sleepDurationSec: Double? = nil,
        rhrBpm: Double? = nil,
        bodyBatteryAvg: Double? = nil,
        readinessScore: Double? = nil,
        acwr: Double? = nil,
        hrvWeeklyAvg: Double? = nil
    ) {
        self.date = date
        self.sleepScore = sleepScore
        self.sleepDurationSec = sleepDurationSec
        self.rhrBpm = rhrBpm
        self.bodyBatteryAvg = bodyBatteryAvg
        self.readinessScore = readinessScore
        self.acwr = acwr
        self.hrvWeeklyAvg = hrvWeeklyAvg
    }
}
public struct RecoveryReport: Codable, Sendable, Equatable {
    public var days: [RecoveryDay]
    public init(days: [RecoveryDay]) { self.days = days }
}
