import JICore
#if canImport(HealthKit)
import HealthKit
#endif

extension DataCapability {
    /// What the Apple Watch / HealthKit **read** path (T2) supplies once permission is granted,
    /// as a `DataCapability` bitmap — distinct from `.hubAll` (T1, Mac hub / Garmin Fenix depth,
    /// `Capabilities.swift`). Same app-feature domains as `.hubAll` (once uploaded, HealthKit data
    /// lands as `dso_key = 4` and feeds the same hub endpoints — see W2d card §Frozen contract),
    /// minus the YAZIO-only nutrition/weigh-in domains (nothing to do with HealthKit) and minus
    /// the metric flags: `.hrvSDNN` is always yes, `.hrvRMSSD` only when the iOS 27 type exists
    /// (`HKReadKind.hrvRMSSDTypeAvailable`), and `.bodyBattery`/`.trainingReadiness`/
    /// `.garminSleepScore` are NEVER set here — those are Garmin/Firstbeat-derived signals
    /// HealthKit cannot supply (memory `project_source_agnostic_gate`: Apple/Garmin don't align).
    ///
    /// W-FIX10 F10-4 (audit 03-F12): `.gate` / `.morning` / `.morningVerdict` are NOT claimed —
    /// `HealthKitProvider` always throws `notCapable(.gate)` for them until the on-device gate
    /// exists (proposal §4), so a consumer reading this bitmap (Today's gate source) goes to the
    /// hub instead of a provider that can only refuse.
    public static var appleWatchCapabilities: DataCapability {
        var caps: DataCapability = [
            .recovery, .sleepSummary, .exercises, .energy,
            .goals, .kpiTargets, .sync, .dataQuality, .hrvSDNN,
        ]
        #if canImport(HealthKit)
        if HKReadKind.hrvRMSSDTypeAvailable { caps.insert(.hrvRMSSD) }
        #endif
        return caps
    }
}
