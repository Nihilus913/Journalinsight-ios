import Foundation
import JICore
import JIDesign

/// B-57 W1 Recovery squares (board: HRV · Sleep · Resting HR · Load). Order/visibility are a
/// per-device UI pref (`@AppStorage` in RecoveryView), comma-joined ids.
public nonisolated let recoveryTileIds = ["hrv", "sleep", "rhr", "load"]

/// Board `2 Monitor/01 Recovery.png`: the "Last night" squares sit two a row.
public nonisolated let recoveryGridColumns = 2

public nonisolated struct RecoveryTileLayout: Equatable, Sendable { public let visible: [String], hidden: [String] }

public nonisolated func recoveryTileLayout(orderRaw: String, hiddenRaw: String) -> RecoveryTileLayout {
    let saved = orderRaw.split(separator: ",").map(String.init).filter { recoveryTileIds.contains($0) }
    var order: [String] = []
    for id in saved + recoveryTileIds where !order.contains(id) { order.append(id) }
    let hidden = Set(hiddenRaw.split(separator: ",").map(String.init))
    return RecoveryTileLayout(visible: order.filter { !hidden.contains($0) }, hidden: order.filter { hidden.contains($0) })
}

/// The newest non-nil reading and the night it came from.
private nonisolated func newest(_ days: [RecoveryDay], _ f: (RecoveryDay) -> Double?) -> (value: Double, date: String)? {
    for d in days.sorted(by: { $0.date > $1.date }) { if let v = f(d) { return (v, d.date) } }
    return nil
}

/// W-FIX1 BUG-05/06/12: the "Last night" squares show a night's value only while it IS last night
/// (≤ 36 h, `KpiMetrics.isLastNightFresh`), with its date when that is not today; older is "— No
/// data", never a stale number passed off as current. HRV is the nightly value (never the hub's
/// 7-day `hrv_weekly_avg` mix) and Load a real ACWR (never the hub's invented 0.00).
public nonisolated func recoveryTileItems(days: [RecoveryDay], layout: RecoveryTileLayout, editing: Bool, now: Date = Date()) -> [JISquareItem] {
    let today = String(now.ISO8601Format().prefix(10))
    func night(_ f: (RecoveryDay) -> Double?) -> (value: Double, date: String)? {
        newest(days, f).flatMap { KpiMetrics.isLastNightFresh(nightDate: $0.date, now: now) ? $0 : nil }
    }
    func item(_ id: String) -> JISquareItem {
        let (label, reading, unit, decimals): (String, (value: Double, date: String)?, String?, Int) = switch id {
        case "hrv": ("HRV", night { KpiMetrics.nightlyHrvMs($0) }, "ms", 0)
        case "sleep": ("Sleep", night { $0.sleepDurationSec.map { ($0 / 3600 * 10).rounded() / 10 } }, "h", 1)
        case "rhr": ("Resting HR", night { $0.rhrBpm }, "bpm", 0)
        default: ("Load", night { KpiMetrics.honestAcwr($0.acwr) }, nil, 2)   // BUG-12: stale Load = "—"
        }
        // W-KEYS D2r (Toby D2): the icon is the descriptor's ("load" → acwr through the one alias map).
        let symbol = KpiMetricId(normalizing: id).map { KpiMetrics.def($0).symbol } ?? "square"
        let value = reading?.value
        // W1: a real value carries no status word (the normal is W3); missing = "— No data".
        return JISquareItem(id: id, label: label, systemImage: symbol, tint: metricTintRole(id), value: value, decimals: decimals,
                            unit: unit, goalText: kpiAsOfLabel(valueDate: reading?.date, today: today),
                            status: value == nil ? .missing(.noData) : nil, badge: editing ? .hide : .none)
    }
    return layout.visible.map(item)
}

public nonisolated func recoveryNightLabel(_ day: String) -> String {
    guard let k = DayKey(iso: day) else { return day } // W-FIX13 F-1: the key's own weekday
    let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    return symbols[k.weekday - 1]
}

public nonisolated func recoveryHrvNights(days: [RecoveryDay]) -> [NormalBarPoint] { recoveryNights(days: days, metric: .hrv) }

// MARK: - W-GUI R1 (mockup 03): the three metric cards, pure

/// The metrics Recovery draws as cards (in this order); Load and the rest are "Also watching".
public nonisolated enum RecoveryCardMetric: String, CaseIterable, Sendable, Equatable {
    case hrv, rhr, sleep
    public var title: String { switch self { case .hrv: "Overnight HRV"; case .rhr: "Resting HR"; case .sleep: "Sleep" } }
    /// W-KEYS D2r (Toby D2): the descriptor's one symbol per metric (was `heart.fill` / `moon.fill`).
    public var symbol: String { KpiMetrics.def(metric).symbol }
    public var metric: KpiMetricId { switch self { case .hrv: .hrv; case .rhr: .rhr; case .sleep: .sleep } }
    public var unit: String { switch self { case .hrv: "ms RMSSD"; case .rhr: "bpm"; case .sleep: "score" } }
    public var decimals: Int { 0 }
    /// The square id the card's tap opens (`openKpiDetail`).
    public var kpiId: String { rawValue }
    public var tint: JIColorRole { metricTintRole(rawValue) }
    nonisolated func value(_ d: RecoveryDay) -> Double? {
        switch self { case .hrv: KpiMetrics.nightlyHrvMs(d); case .rhr: d.rhrBpm; case .sleep: d.sleepScore }
    }
}

/// The last 7 nights of a card's metric as chart points (missing nights stay missing).
public nonisolated func recoveryNights(days: [RecoveryDay], metric: RecoveryCardMetric) -> [NormalBarPoint] {
    let last = days.sorted { $0.date < $1.date }.suffix(7)
    return last.enumerated().map { i, d in
        NormalBarPoint(id: d.date, label: recoveryNightLabel(d.date), value: metric.value(d), isLatest: i == last.count - 1)
    }
}

/// The card's headline: last night's value while it is last night (BUG-05/06 rule, same as the
/// squares), else nil — with its date word.
public nonisolated func recoveryCardReading(days: [RecoveryDay], metric: RecoveryCardMetric, now: Date = Date()) -> (value: Double?, asOf: String?) {
    let today = String(now.ISO8601Format().prefix(10))
    guard let r = newest(days, metric.value), KpiMetrics.isLastNightFresh(nightDate: r.date, now: now) else { return (nil, nil) }
    return (r.value, kpiAsOfLabel(valueDate: r.date, today: today))
}

/// "your normal 27–30" once the band exists (W3); until then "your normal —" (never a number).
public nonisolated func recoveryNormalText(_ normal: ClosedRange<Double>?, decimals: Int = 0) -> String {
    normal.map { "your normal \(jiNumber($0.lowerBound, decimals))–\(jiNumber($0.upperBound, decimals))" } ?? "your normal —"
}

/// A sleep fact tile's value: "7 h 24" from seconds; "— not read" when the field is absent.
public nonisolated func recoverySleepDuration(seconds: Double?) -> String {
    guard let seconds, seconds > 0 else { return "— not read" }
    return DurationFormat.hoursPaddedMinutes(seconds: seconds)
}

public nonisolated func recoverySubtitle(nights: Int) -> String {
    "How you are trending · \(nights) night\(nights == 1 ? "" : "s")"
}
public nonisolated let recoveryMonitorCaption = "Trends only. Nothing on this screen decides your day, and none of it is a medical reading."
public nonisolated let recoveryRhrCaption = "Overnight only. Daytime HR is not used."

