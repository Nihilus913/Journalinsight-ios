import Foundation
import JICore

/// W3a-L2 (P-nutrition). `HubDataProvider.swift` is frozen this wave (three screen lanes would
/// collide on it) — this file only adds a new protocol conformance in its own file, per the wave
/// card's Data seam.
extension HubDataProvider: NutritionProviding {
    /// `GET /api/v1/nutrition/daily?date=` doesn't exist — that endpoint (`app/nutrition/router.py`
    /// `get_nutrition`) takes only `window_days` and ignores `date`, returning a `days[]` report
    /// (`NutritionReportResponse`), never a `{date,total,breakdown,items}` object. The real
    /// day-detail-with-meals endpoint is `GET /api/v1/training/day/{date}`
    /// (`app/training/router.py` `DayDetailResponse.meals`) — see `NutritionDayEnvelope`.
    public func nutritionDay(date: String) async throws -> NutritionDayDetail? {
        let envelope: NutritionDayEnvelope = try await nutritionHubClient.get("/api/v1/training/day/\(date)")
        return envelope.detail
    }

    public func nutritionWeek(windowDays: Int = 7) async throws -> [NutritionDailyRow] {
        let r: NutritionReportResponse = try await nutritionHubClient.get("/api/v1/nutrition/daily", query: ["window_days": String(min(windowDays, 365))])
        return r.days
    }

    public func logFood(_ body: LogFoodBody) async throws -> LogFoodResult {
        try await nutritionHubClient.post("/api/v1/nutrition/log", body: body)
    }

    /// `HubClient` has no DELETE helper (card: "add a DELETE helper in `HubDataProvider+Nutrition.swift`
    /// only if `HubClient` lacks one — do not edit `HubClient.swift`") — this mirrors `HubClient.get`'s
    /// own status-mapping and ephemeral-session handling for the one hub call that returns no body.
    public func deleteLogItem(itemId: String, date: String?) async throws {
        let client = nutritionHubClient
        var comps = URLComponents(url: client.config.baseURL.appending(path: "/api/v1/nutrition/log/\(itemId)"), resolvingAgainstBaseURL: false)!
        if let date { comps.queryItems = [URLQueryItem(name: "date", value: date)] }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 15
        req.setValue("Bearer \(client.config.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let session = HubClient.makeDefaultSession()
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) } catch { throw HubError.network(error.localizedDescription) }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSON.decoder.decode([String: String].self, from: data))?["detail"]
            throw HubError.from(status: status, detail: detail)
        }
    }
}

/// `HubDataProvider.client` is `private` in the frozen `HubDataProvider.swift` — Swift's `private`
/// doesn't reach an extension in a different file, and this wave's Data seam forbids editing that
/// file to widen it (three screen lanes would collide there). `Mirror` is the only zero-edit path
/// to the stored `HubClient` this extension needs; flagged for a real `internal`/`public` accessor
/// in a follow-up wave once L1/L3 (the sibling screen lanes hitting the identical wall) land.
private extension HubDataProvider {
    var nutritionHubClient: HubClient {
        guard let client = Mirror(reflecting: self).children.first(where: { $0.label == "client" })?.value as? HubClient else {
            preconditionFailure("HubDataProvider.client not reachable via reflection — frozen file layout changed")
        }
        return client
    }
}
