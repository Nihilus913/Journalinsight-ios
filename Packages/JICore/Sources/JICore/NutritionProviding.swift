import Foundation

/// W3a-L2 (P-nutrition) — this screen's own protocol, added fresh this wave rather than growing
/// the frozen `HealthDataProvider` (see the wave card's "Data seam": `HealthDataProvider` /
/// `HubDataProvider` / `MockDataProvider` are frozen; each screen lane adds its own protocol in a
/// new file instead, so three parallel lanes never collide on one shared interface).
public protocol NutritionProviding: Sendable {
    /// `GET /api/v1/training/day/{date}` (`meals` slice) — the meal-timeline detail for one day.
    /// `nutrition/daily` takes only `window_days` and ignores `date`, so it cannot serve this; see
    /// `NutritionDayEnvelope`. `nil` only when the hub genuinely has no row for that date (never a
    /// zeroed-out `NutritionDayDetail`).
    func nutritionDay(date: String) async throws -> NutritionDayDetail?
    /// `GET /api/v1/nutrition/daily?window_days=` — the week strip's per-day totals.
    func nutritionWeek(windowDays: Int) async throws -> [NutritionDailyRow]
}
