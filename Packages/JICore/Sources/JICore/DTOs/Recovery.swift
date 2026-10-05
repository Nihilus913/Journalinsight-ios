public struct RecoveryDay: Codable, Sendable, Equatable {
    public var date: String
    public var sleepScore, sleepDurationSec, rhrBpm, bodyBatteryAvg, readinessScore, acwr, hrvWeeklyAvg: Double?
    /// W-FIX1 BUG-06: that night's own RMSSD (`/vitals/recovery` `hrv_rmssd_ms`, from
    /// `core.daily_vitals.hrv_rmssd_ms`). A night — unlike `hrvWeeklyAvg`, the hub's 7-day mix.
    /// Optional on the wire: a hub that predates the field decodes to nil ("—").
    public var hrvRmssdMs: Double?
    /// W-FIX-P1 RG-07 (B-122): the complete day `acwr` is for (`acwr_as_of`). Today's row carries
    /// the gate's last-complete-day ratio, so this names yesterday. Nil from an older hub.
    public var acwrAsOf: String? = nil
    /// W-DATA R6: fields `/vitals/recovery` already serves (FM-09) — sleep stages, Garmin body
    /// battery low/high and recovery time. Optional on the wire; nil = "— not read", never 0.
    public var deepSleepSec, lightSleepSec, remSleepSec: Double?
    public var bodyBatteryMin, bodyBatteryMax, recoveryTimeMin: Double?
    /// W-DATA R4: the night's respiration (breaths/min, `core.daily_vitals.resp_sleep_avg`) and
    /// sleeping wrist temperature (°C) with its deviation from the user's own baseline —
    /// `wristTempDevC` is nil while calibrating (`wristTempBaselineNights` < 5). Never clinical.
    public var respSleepAvg, wristTempC, wristTempDevC, wristTempBaselineNights: Double?

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
        hrvWeeklyAvg: Double? = nil,
        hrvRmssdMs: Double? = nil,
        deepSleepSec: Double? = nil,
        lightSleepSec: Double? = nil,
        remSleepSec: Double? = nil,
        bodyBatteryMin: Double? = nil,
        bodyBatteryMax: Double? = nil,
        recoveryTimeMin: Double? = nil,
        respSleepAvg: Double? = nil,
        wristTempC: Double? = nil,
        wristTempDevC: Double? = nil,
        wristTempBaselineNights: Double? = nil
    ) {
        self.date = date
        self.sleepScore = sleepScore
        self.sleepDurationSec = sleepDurationSec
        self.rhrBpm = rhrBpm
        self.bodyBatteryAvg = bodyBatteryAvg
        self.readinessScore = readinessScore
        self.acwr = acwr
        self.hrvWeeklyAvg = hrvWeeklyAvg
        self.hrvRmssdMs = hrvRmssdMs
        self.deepSleepSec = deepSleepSec
        self.lightSleepSec = lightSleepSec
        self.remSleepSec = remSleepSec
        self.bodyBatteryMin = bodyBatteryMin
        self.bodyBatteryMax = bodyBatteryMax
        self.recoveryTimeMin = recoveryTimeMin
        self.respSleepAvg = respSleepAvg
        self.wristTempC = wristTempC
        self.wristTempDevC = wristTempDevC
        self.wristTempBaselineNights = wristTempBaselineNights
    }
}
public struct RecoveryReport: Codable, Sendable, Equatable {
    public var days: [RecoveryDay]
    /// W-FIX13 F-7: the Today tile's night; nil from a hub that predates it.
    public var lastNight: RecoveryLastNight?
    public init(days: [RecoveryDay], lastNight: RecoveryLastNight? = nil) { self.days = days; self.lastNight = lastNight }
}
