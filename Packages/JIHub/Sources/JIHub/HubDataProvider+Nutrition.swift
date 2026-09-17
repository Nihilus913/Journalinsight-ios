import Foundation
import JICore

/// W3a-L2 (P-nutrition). L0 (W3b, B-14) widened `HubDataProvider.client` to internal, so this
/// extension now uses it directly — the `Mirror`-based workaround and the hand-rolled DELETE
/// request this file carried during W3a are gone in favor of `HubClient.delete`.
extension HubDataProvider: NutritionProviding {
    /// `GET /api/v1/nutrition/daily?date=` doesn't exist — that endpoint (`app/nutrition/router.py`
    /// `get_nutrition`) takes only `window_days` and ignores `date`, returning a `days[]` report
    /// (`NutritionReportResponse`), never a `{date,total,breakdown,items}` object. The real
    /// day-detail-with-meals endpoint is `GET /api/v1/training/day/{date}`
    /// (`app/training/router.py` `DayDetailResponse.meals`) — see `NutritionDayEnvelope`.
    public func nutritionDay(date: String) async throws -> NutritionDayDetail? {
        let envelope: NutritionDayEnvelope = try await client.get("/api/v1/training/day/\(date)")
        return envelope.detail
    }

    public func nutritionWeek(windowDays: Int = 7) async throws -> [NutritionDailyRow] {
        let r: NutritionReportResponse = try await client.get("/api/v1/nutrition/daily", query: ["window_days": String(min(windowDays, 365))])
        return r.days
    }

    public func logFood(_ body: LogFoodBody) async throws -> LogFoodResult {
        try await client.post("/api/v1/nutrition/log", body: body)
    }

    public func deleteLogItem(itemId: String, date: String?) async throws {
        var query: [String: String] = [:]
        if let date { query["date"] = date }
        try await client.delete("/api/v1/nutrition/log/\(itemId)", query: query)
    }
}
