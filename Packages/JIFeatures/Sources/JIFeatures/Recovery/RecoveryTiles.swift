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
        let (label, symbol, reading, unit, decimals): (String, String, (value: Double, date: String)?, String?, Int) = switch id {
        case "hrv": ("HRV", "waveform.path.ecg", night { KpiMetrics.nightlyHrvMs($0) }, "ms", 0)
        case "sleep": ("Sleep", "moon", night { $0.sleepDurationSec.map { ($0 / 3600 * 10).rounded() / 10 } }, "h", 1)
        case "rhr": ("Resting HR", "heart", night { $0.rhrBpm }, "bpm", 0)
        default: ("Load", "bolt", newest(days) { KpiMetrics.honestAcwr($0.acwr) }, nil, 2)
        }
        let value = reading?.value
        // W1: a real value carries no status word (the normal is W3); missing = "— No data".
        return JISquareItem(id: id, label: label, systemImage: symbol, tint: metricTintRole(id), value: value, decimals: decimals,
                            unit: unit, goalText: kpiAsOfLabel(valueDate: reading?.date, today: today),
                            status: value == nil ? .missing(.noData) : nil, badge: editing ? .hide : .none)
    }
    return layout.visible.map(item)
}

public nonisolated func recoveryNightLabel(_ day: String) -> String {
    guard let d = recoveryTrendDate(day) else { return day }
    var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    return symbols[c.component(.weekday, from: d) - 1]
}

public nonisolated func recoveryHrvNights(days: [RecoveryDay]) -> [NormalBarPoint] {
    let last = days.sorted { $0.date < $1.date }.suffix(7)
    return last.enumerated().map { i, d in
        NormalBarPoint(id: d.date, label: recoveryNightLabel(d.date), value: KpiMetrics.nightlyHrvMs(d), isLatest: i == last.count - 1)
    }
}
