import Foundation

/// Previews + tests only (same rule as `MockDataProvider` itself — never the app default).
/// Duplicates the tiny fixture-loading helper rather than reusing `MockDataProvider.load`: that
/// method is `private` in `MockDataProvider.swift`, which is frozen this wave (see the wave
/// card's Data seam) and Swift's `private` doesn't reach across files even for an extension of
/// the same type — `MockDataProvider.fixtureURL(named:)` is the public seam this file uses
/// instead.
extension MockDataProvider: NutritionProviding {
    private func loadNutritionFixture<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        guard let url = MockDataProvider.fixtureURL(named: name)
        else { throw HubError.decoding("missing fixture \(name)") }
        return try JSON.decoder.decode(T.self, from: Data(contentsOf: url))
    }

    public func nutritionDay(date: String) async throws -> NutritionDayDetail? {
        try loadNutritionFixture("nutrition_daily_day", as: NutritionDayDetail.self)
    }

    public func nutritionWeek(windowDays: Int) async throws -> [NutritionDailyRow] {
        try loadNutritionFixture("nutrition_daily_week", as: NutritionReportResponse.self).days
    }

    /// No hub to actually write to — echoes the posted body back as a synthesized `LogFoodResult`
    /// (previews only; view-model tests exercising the 409/502 UI contract use their own fake
    /// `NutritionProviding`, not this mock).
    public func logFood(_ body: LogFoodBody) async throws -> LogFoodResult {
        // A template body carries no `items` (the server expands it) — echo one synthetic line
        // so preview/test callers driving the template flow still see a logged item, same as a
        // manual `items` list would.
        let items = body.items ?? (body.template.map { [LogFoodItemInput(name: $0, kcal: 0)] } ?? [])
        let logged = items.enumerated().map { i, item in
            LoggedFoodItem(itemId: "mock-\(i)", name: item.name, meal: body.meal?.rawValue, kcal: item.kcal, proteinG: item.proteinG, carbsG: item.carbsG, fatG: item.fatG)
        }
        return LogFoodResult(logged: logged, date: body.date ?? "2026-09-17")
    }

    public func deleteLogItem(itemId: String, date: String?) async throws {}
}
