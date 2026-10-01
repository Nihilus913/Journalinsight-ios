import Foundation
import JICore
import JICompute
import JIDesign

/// W-DATA R9 (fixer): Load from the gate's own inputs (`/vitals/recovery-inputs` `load_min`, which
/// the hub derives from Apple exercise minutes), with its band. It is the SAME number the recovery
/// score's load component uses (`RecoveryScore.compute`): the 7-day load ending yesterday, in
/// minutes, against the 28-day normal of 7-day loads (`loadMinNormalN` values; fewer = Calibrating).
/// ACWR stays the fallback for a hub that serves one; Apple never does, so Load was "— No data".
public nonisolated struct RecoveryLoadReading: Equatable, Sendable {
    /// Minutes over the 7 days ending yesterday.
    public let minutes: Double
    /// The personal normal of 7-day loads; nil while calibrating.
    public let normal: PersonalNormalResult?
    /// The last 7 days' daily `load_min`, oldest first (a day without a value is nil, never 0).
    public let points: [Double?]

    /// The tile caption: "7 d · normal 180–320", or "7 d · Calibrating" (never a number). Short:
    /// it sits on a three-up tile.
    public var caption: String {
        guard let normal else { return "7 d · \(JIMissingReason.calibrating.rawValue)" }
        return "7 d · normal \(jiNumber(normal.low, 0))–\(jiNumber(normal.high, 0))"
    }

    /// VoiceOver: the whole sentence.
    public var accessibilityText: String {
        let band = normal.map { "your normal \(jiNumber($0.low, 0)) to \(jiNumber($0.high, 0))" } ?? JIMissingReason.calibrating.rawValue
        return "Load \(valueText) over 7 days, \(band)"
    }

    /// The tile value: "245 min".
    public var valueText: String { "\(jiNumber(minutes, 0)) min" }
}

/// nil when fewer than `RecoveryScore.loadMinDaysInWeek` of the last 7 days carry a load.
public nonisolated func recoveryLoadReading(days: [RecoveryInputDay], today: String) -> RecoveryLoadReading? {
    guard !today.isEmpty else { return nil }
    var daily: [String: Double] = [:]
    for d in days { if let v = d.loadMin, v.isFinite, v >= 0 { daily[d.date] = v } }
    do {
        let yesterday = try CalendarMath.addDays(today, -1)
        guard let minutes = try RecoveryScore.load7(daily, end: yesterday) else { return nil }
        var weekly: [String: Double] = [:]
        var d = try PersonalNormal.window(today: today).start
        while d <= yesterday {
            if let v = try RecoveryScore.load7(daily, end: d) { weekly[d] = v }
            d = try CalendarMath.addDays(d, 1)
        }
        let normal = try PersonalNormal.normal(weekly, today: today, minN: RecoveryScore.loadMinNormalN)
        let points: [Double?] = try (0..<7).reversed().map { daily[try CalendarMath.addDays(today, -$0)] }
        return RecoveryLoadReading(minutes: minutes, normal: normal, points: points)
    } catch {
        return nil
    }
}

extension RecoveryInsightService {
    /// W-DATA R9: the Load reading over the loaded inputs; nil before a load or without data.
    /// W-FIX10 R-04: while the hub calibrates `load`, the minutes stay but the band does not.
    public var loadReading: RecoveryLoadReading? {
        guard let r = recoveryLoadReading(days: days, today: today) else { return nil }
        guard calibration?.isCalibrating("load") ?? false else { return r }
        return RecoveryLoadReading(minutes: r.minutes, normal: nil, points: r.points)
    }
}

/// W-DATA R9: Today's "Load" square. An ACWR the hub really sent keeps the square; otherwise the
/// gate-input load (minutes, with its band as the caption) fills it. Every other chip is unchanged.
public nonisolated func todayChipsWithLoad(_ chips: [TodayChip], load: RecoveryLoadReading?) -> [TodayChip] {
    guard let load else { return chips }
    return chips.map { chip in
        guard chip.id == "acwr", chip.value == nil else { return chip }
        return TodayChip(id: chip.id, label: chip.label, value: load.minutes.rounded(), unit: recoveryLoadUnit,
                         points: load.points, sourceMissing: false, asOf: load.caption)
    }
}

/// The unit a minutes-Load chip carries (the square then rounds to whole minutes, not ACWR's 2 dp).
public nonisolated let recoveryLoadUnit = "min"
