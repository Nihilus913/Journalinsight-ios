import Foundation
import JICore
import JIDesign

/// B-57 W1 Recovery squares (board: HRV · Sleep · Resting HR · Load). Order/visibility are a
/// per-device UI pref (`@AppStorage` in RecoveryView), comma-joined ids.
public nonisolated let recoveryTileIds = ["hrv", "sleep", "rhr", "load"]

public nonisolated struct RecoveryTileLayout: Equatable, Sendable { public let visible: [String], hidden: [String] }

public nonisolated func recoveryTileLayout(orderRaw: String, hiddenRaw: String) -> RecoveryTileLayout {
    let saved = orderRaw.split(separator: ",").map(String.init).filter { recoveryTileIds.contains($0) }
    var order: [String] = []
    for id in saved + recoveryTileIds where !order.contains(id) { order.append(id) }
    let hidden = Set(hiddenRaw.split(separator: ",").map(String.init))
    return RecoveryTileLayout(visible: order.filter { !hidden.contains($0) }, hidden: order.filter { hidden.contains($0) })
}

private nonisolated func newest(_ days: [RecoveryDay], _ f: (RecoveryDay) -> Double?) -> Double? {
    days.sorted { $0.date > $1.date }.lazy.compactMap(f).first
}

public nonisolated func recoveryTileItems(days: [RecoveryDay], layout: RecoveryTileLayout, editing: Bool) -> [JISquareItem] {
    func item(_ id: String) -> JISquareItem {
        let (label, symbol, value, unit, decimals): (String, String, Double?, String?, Int) = switch id {
        case "hrv": ("HRV", "waveform.path.ecg", newest(days) { $0.hrvWeeklyAvg }, "ms", 0)
        case "sleep": ("Sleep", "moon", newest(days) { $0.sleepDurationSec.map { ($0 / 3600 * 10).rounded() / 10 } }, "h", 1)
        case "rhr": ("Resting HR", "heart", newest(days) { $0.rhrBpm }, "bpm", 0)
        default: ("Load", "bolt", newest(days) { $0.acwr }, nil, 2)
        }
        // W1: a real value carries no status word (the normal is W3); missing = "— No data".
        return JISquareItem(id: id, label: label, systemImage: symbol, tint: metricTintRole(id), value: value, decimals: decimals,
                            unit: unit, status: value == nil ? .missing(.noData) : nil, badge: editing ? .hide : .none)
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
        NormalBarPoint(id: d.date, label: recoveryNightLabel(d.date), value: d.hrvWeeklyAvg, isLatest: i == last.count - 1)
    }
}
