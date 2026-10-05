import Foundation

/// B-91 S3 (b91p1) — daily Strain 0-100. Verbatim port of `app/vitals/strain.py`
/// (`percentile`, `strain_from_load`, `strain_summary`), pinned by the HT golden
/// `tests/fixtures/strain.golden.json` (byte-copied into the test bundle).
///
///     L(d)   = the day's session load (ACWR currency, from the hub's core.activity).
///     k      = p90 (linear interpolation) of L over the LOADED days (L > 0) of the
///              trailing 120 days BEFORE today.
///     Strain = 100 x (1 - exp(-L / k)), Python-rounded to 0.1. 0 on a day without load.
///     usual  = p25..p75 of Strain over those same loaded days, Python-rounded to int.
///
/// Fewer than 19 loaded days in the window = "calibrating": no ceiling, no usual range,
/// no strain values (never a guessed number).
///
/// NOT wired into Decide (card Q1 default): the hub stays the source; B-44 dual-run
/// decides when the local value is trusted. "Max today" is NOT computed here — it follows
/// the decided call only (DecideStrainCeiling).
public nonisolated enum StrainStatus: String, Sendable, Hashable, Codable { case calibrating, ok }

public nonisolated struct StrainDay: Hashable, Sendable {
    public let date: String
    /// nil while calibrating.
    public let value: Double?
    public init(date: String, value: Double?) { self.date = date; self.value = value }
}

public nonisolated struct StrainSummary: Hashable, Sendable {
    public let status: StrainStatus
    public let loadedDays: Int
    public let minLoadedDays: Int
    public let windowDays: Int
    /// k rounded to 4 decimals (Python `round(k, 4)`); nil while calibrating.
    public let ceiling: Double?
    public let usualLow: Int?
    public let usualHigh: Int?
    public let yesterday: StrainDay
    public let today: StrainDay
}

public nonisolated enum Strain {
    /// The `ParityRegistry` key this type implements.
    public static let registryKey = "daily_strain"

    public static let windowDays = 120
    public static let minLoadedDays = 19
    public static let ceilingPercentile = 0.90
    public static let usualLowPercentile = 0.25
    public static let usualHighPercentile = 0.75

    /// Linear-interpolation percentile (numpy 'linear'), same arithmetic order as Python.
    /// nil for an empty list (Python raises).
    public static func percentile(_ values: [Double], _ q: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let pos = Double(s.count - 1) * q
        let lo = Int(pos.rounded(.down))
        let hi = Int(pos.rounded(.up))
        if lo == hi { return s[lo] }
        return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
    }

    /// Strain 0-100 for one day's load against the personal ceiling k.
    public static func strainFromLoad(_ load: Double, ceiling: Double) -> Double {
        if load <= 0 || ceiling <= 0 { return 0.0 }
        return pythonRound(100.0 * (1.0 - exp(-load / ceiling)), 1)
    }

    /// The Strain card's numbers for `today` (ISO date) from per-day loads keyed by ISO date
    /// (missing day = 0 load).
    public static func summary(loads: [String: Double], today: String) throws -> StrainSummary {
        let todayDays = try CalendarMath.parseDays(today)
        let start = todayDays - windowDays
        var history: [Double] = []
        for (iso, v) in loads where v > 0 {
            let d = try CalendarMath.parseDays(iso)
            if start <= d && d < todayDays { history.append(v) }
        }
        let yesterdayISO = CalendarMath.isoString(fromDays: todayDays - 1)
        let todayISO = CalendarMath.isoString(fromDays: todayDays)
        guard history.count >= minLoadedDays,
              let k = percentile(history, ceilingPercentile) else {
            return StrainSummary(status: .calibrating, loadedDays: history.count, minLoadedDays: minLoadedDays,
                                 windowDays: windowDays, ceiling: nil, usualLow: nil, usualHigh: nil,
                                 yesterday: StrainDay(date: yesterdayISO, value: nil),
                                 today: StrainDay(date: todayISO, value: nil))
        }
        let strains = history.map { strainFromLoad($0, ceiling: k) }
        let low = percentile(strains, usualLowPercentile).map { Int(pythonRound($0)) }
        let high = percentile(strains, usualHighPercentile).map { Int(pythonRound($0)) }
        return StrainSummary(status: .ok, loadedDays: history.count, minLoadedDays: minLoadedDays,
                             windowDays: windowDays, ceiling: pythonRound(k, 4), usualLow: low, usualHigh: high,
                             yesterday: StrainDay(date: yesterdayISO, value: strainFromLoad(loads[yesterdayISO] ?? 0, ceiling: k)),
                             today: StrainDay(date: todayISO, value: strainFromLoad(loads[todayISO] ?? 0, ceiling: k)))
    }
}
