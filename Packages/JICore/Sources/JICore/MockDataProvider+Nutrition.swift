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

    /// Fixture is a real `GET /api/v1/training/day/{date}` capture (see `NutritionDayEnvelope`) —
    /// not the flat `NutritionDayDetail` shape, which no real endpoint produces.
    public func nutritionDay(date: String) async throws -> NutritionDayDetail? {
        try loadNutritionFixture("nutrition_daily_day", as: NutritionDayEnvelope.self).detail
    }

    public func nutritionWeek(windowDays: Int) async throws -> [NutritionDailyRow] {
        try loadNutritionFixture("nutrition_daily_week", as: NutritionReportResponse.self).days
    }

}
