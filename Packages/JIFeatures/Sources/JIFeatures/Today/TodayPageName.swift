import Foundation
import JIPersistence

/// B-57 W1 EditToday "Page name" (board: "offer edit name"). Stored in PrefStore; the Today
/// navigation title reads it. Default "Today".
public nonisolated let todayPageNameKey = "today.pageName"
public nonisolated let todayPageNameDefault = "Today"

public nonisolated func normalizedTodayPageName(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? todayPageNameDefault : String(trimmed.prefix(24))
}

public nonisolated func loadTodayPageName(prefs: PrefStore?) -> String {
    let stored = (try? prefs?.get(todayPageNameKey, as: String.self)) ?? nil
    return normalizedTodayPageName(stored ?? "")
}

public nonisolated func saveTodayPageName(_ name: String, prefs: PrefStore?) {
    try? prefs?.set(todayPageNameKey, normalizedTodayPageName(name))
}
