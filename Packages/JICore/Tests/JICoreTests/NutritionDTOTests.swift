import Foundation
import Testing
@testable import JICore

@Test func nutritionDayDetailDecodesFromFixtureNeverZero() throws {
    // Fixture is a real `GET /api/v1/training/day/{date}` capture (the endpoint that actually
    // carries meal-timeline data) — decode the envelope, same path production code takes.
    let url = try #require(MockDataProvider.fixtureURL(named: "nutrition_daily_day"))
    let envelope = try JSON.decoder.decode(NutritionDayEnvelope.self, from: Data(contentsOf: url))
    let day = try #require(envelope.detail)
    #expect(day.date == "2026-09-11")
    #expect(day.total.kcal == 1028.8)
    #expect(day.breakdown.dinner == nil, "missing dinner must decode nil, never 0 (rule 5)")
    let breakfast = try #require(day.items["breakfast"])
    #expect(breakfast.count == 2)
    #expect(breakfast[1].fatG == nil, "missing item fat must decode nil, never 0 (rule 5)")
}

@Test func nutritionWeekDecodesFromFixtureAndKeepsNullDaysNil() throws {
    let url = try #require(MockDataProvider.fixtureURL(named: "nutrition_daily_week"))
    let week = try JSON.decoder.decode(NutritionReportResponse.self, from: Data(contentsOf: url)).days
    #expect(week.count == 7)
    let synced = try #require(week.first)
    #expect(synced.kcalConsumed == 1028.8)
    let unsynced = try #require(week.last)
    #expect(unsynced.kcalConsumed == nil, "an unsynced day must decode nil, never 0 (rule 5)")
}

@Test func logFoodBodyEncodesTemplateVariant() throws {
    let body = LogFoodBody(meal: .breakfast, template: "breakfast_default")
    let data = try JSON.encoder.encode(body)
    let decoded = try JSON.decoder.decode(LogFoodBody.self, from: data)
    #expect(decoded.meal == .breakfast)
    #expect(decoded.template == "breakfast_default")
    #expect(decoded.items == nil)
}

@Test func logFoodResultDecodesHubEcho() throws {
    let json = """
    {"logged": [{"item_id": "abc123", "name": "Toast", "meal": "breakfast", "kcal": 200.0, "protein_g": 6.0, "carbs_g": 30.0, "fat_g": 5.0}], "date": "2026-09-17"}
    """.data(using: .utf8)!
    let result = try JSON.decoder.decode(LogFoodResult.self, from: json)
    #expect(result.date == "2026-09-17")
    #expect(result.logged.first?.itemId == "abc123")
}

@Test func mockProviderNutritionDayAndWeekLoadFromFixtures() async throws {
    let provider = MockDataProvider()
    let day = try await provider.nutritionDay(date: "2026-09-11")
    #expect(day?.date == "2026-09-11")
    let week = try await provider.nutritionWeek(windowDays: 7)
    #expect(week.count == 7)
}

@Test func mockProviderLogFoodEchoesPostedItems() async throws {
    let provider = MockDataProvider()
    let body = LogFoodBody(meal: .snack, items: [LogFoodItemInput(name: "Apple", kcal: 95)])
    let result = try await provider.logFood(body)
    #expect(result.logged.first?.name == "Apple")
    try await provider.deleteLogItem(itemId: result.logged[0].itemId, date: nil)
}
