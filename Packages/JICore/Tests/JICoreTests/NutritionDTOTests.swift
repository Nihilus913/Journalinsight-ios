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

@Test func mockProviderNutritionDayAndWeekLoadFromFixtures() async throws {
    let provider = MockDataProvider()
    let day = try await provider.nutritionDay(date: "2026-09-11")
    #expect(day?.date == "2026-09-11")
    let week = try await provider.nutritionWeek(windowDays: 7)
    #expect(week.count == 7)
}
