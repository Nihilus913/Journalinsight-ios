import Foundation
import JIDesign

/// B-52 p2 (reads: training) — the one caption a hub-read screen shows when its data came from the
/// offline read-through cache (`HubClient.getRead` → `HubReadTrace`): "Offline — showing data from
/// 07:41" (same day) or "… from 3 Oct, 07:41" (older). Never a blank screen, never a fabricated
/// value: the copy is the hub's last answer, worded as such.
public nonisolated func offlineReadCaption(since: Date, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> String {
    let time = jiShortTime(since, calendar: calendar)
    guard !calendar.isDate(since, inSameDayAs: now) else { return "Offline — showing data from \(time)" }
    let f = DateFormatter()
    f.locale = calendar.locale ?? .autoupdatingCurrent
    f.calendar = calendar
    f.timeZone = calendar.timeZone
    f.setLocalizedDateFormatFromTemplate("dMMM")
    return "Offline — showing data from \(f.string(from: since)), \(time)"
}
