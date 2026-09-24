/// Mass-market seam (spec §4.2): every provider declares what it supplies; tiles read the bitmap,
/// never the provider type. RN's 6-flag version had zero call sites — here every gated tile has a test.
public struct DataCapability: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    // Domains (one per DataProvider method group)
    public static let gate            = DataCapability(rawValue: 1 << 0)
    public static let morning         = DataCapability(rawValue: 1 << 1)
    public static let morningVerdict  = DataCapability(rawValue: 1 << 2)
    public static let recovery        = DataCapability(rawValue: 1 << 3)
    public static let sleepSummary    = DataCapability(rawValue: 1 << 4)
    public static let exercises       = DataCapability(rawValue: 1 << 5)
    public static let energy          = DataCapability(rawValue: 1 << 6)
    public static let nutritionDay    = DataCapability(rawValue: 1 << 7)
    public static let nutritionWeek   = DataCapability(rawValue: 1 << 8)
    // 1 << 9 retired (B-57 W1: food logging removed — JI is read-only for food). Never reuse.
    public static let weighinWrite    = DataCapability(rawValue: 1 << 10)
    public static let goals           = DataCapability(rawValue: 1 << 11)
    public static let kpiTargets      = DataCapability(rawValue: 1 << 12)
    // 1 << 13 retired (B-57 W1 deleted that feature). Never reuse.
    public static let sync            = DataCapability(rawValue: 1 << 14)
    public static let dataQuality     = DataCapability(rawValue: 1 << 15)
    // Metrics that only some sources carry (Garmin/Firstbeat vs HealthKit)
    public static let bodyBattery       = DataCapability(rawValue: 1 << 20)
    public static let trainingReadiness = DataCapability(rawValue: 1 << 21)
    public static let garminSleepScore  = DataCapability(rawValue: 1 << 22)
    public static let hrvRMSSD          = DataCapability(rawValue: 1 << 23)
    public static let hrvSDNN           = DataCapability(rawValue: 1 << 24)

    /// What the Mac hub (T1, Garmin Fenix depth) supplies.
    public static let hubAll: DataCapability = [
        .gate, .morning, .morningVerdict, .recovery, .sleepSummary, .exercises, .energy,
        .nutritionDay, .nutritionWeek, .weighinWrite, .goals, .kpiTargets,
        .sync, .dataQuality, .bodyBattery, .trainingReadiness, .garminSleepScore, .hrvRMSSD,
    ]
}
