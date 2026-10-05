import Foundation
import Testing
import JICore
@testable import JIHub

/// B-99 p4 — `HubDataProvider.nutritionWeek` decodes `days[].diet_quality` (+ `sat_fat_g`,
/// `coverage_pct`) of `GET /api/v1/nutrition/daily`. The fixture is the HT route's real output
/// (HT `tests/fixtures/diet_quality/nutrition_daily_dq.json`, generated from
/// `tests/test_nutrition_daily_dq.py`'s scenario). An extension on the `.serialized`
/// `HubClientTests` suite because `StubURLProtocol` keeps process-global state.
extension HubClientTests {
    private static let nutritionDailyPath = "/api/v1/nutrition/daily"

    static let nutritionDailyDQFixture = #"""
{"days": [{"date": "2026-10-03", "kcal_consumed": 1500.0, "kcal_goal": 1400.0, "protein_g": 100.0, "carbs_g": 150.0, "fat_g": 50.0, "fiber_g": null, "sugar_g": null, "sat_fat_g": null, "coverage_pct": null, "meals_logged": null, "diet_quality": {"score": null, "incomplete": true, "reason": "few_meals", "contributors": [{"key": "fibre", "score": null, "weight": null}, {"key": "sugar", "score": null, "weight": null}, {"key": "sat_fat", "score": null, "weight": null}, {"key": "protein", "score": 83.3, "weight": 1.0}], "coverage_pct": null, "formula_version": 1}}, {"date": "2026-10-02", "kcal_consumed": 1500.0, "kcal_goal": 1400.0, "protein_g": 100.0, "carbs_g": 150.0, "fat_g": 50.0, "fiber_g": null, "sugar_g": null, "sat_fat_g": null, "coverage_pct": 0.0, "meals_logged": 2, "diet_quality": {"score": null, "incomplete": true, "reason": "few_meals", "contributors": [{"key": "fibre", "score": null, "weight": null}, {"key": "sugar", "score": null, "weight": null}, {"key": "sat_fat", "score": null, "weight": null}, {"key": "protein", "score": 83.3, "weight": 1.0}], "coverage_pct": 0, "formula_version": 1}}, {"date": "2026-10-01", "kcal_consumed": 1500.0, "kcal_goal": 1400.0, "protein_g": 100.0, "carbs_g": 150.0, "fat_g": 50.0, "fiber_g": 8.0, "sugar_g": 1.2, "sat_fat_g": 11.0, "coverage_pct": 56.7, "meals_logged": 3, "diet_quality": {"score": 80, "incomplete": false, "reason": null, "contributors": [{"key": "fibre", "score": 38.1, "weight": 0.25}, {"key": "sugar", "score": 100.0, "weight": 0.25}, {"key": "sat_fat", "score": 100.0, "weight": 0.25}, {"key": "protein", "score": 83.3, "weight": 0.25}], "coverage_pct": 57, "formula_version": 1}}], "avg_kcal_7d": 1500.0, "avg_protein_7d": 100.0, "avg_carbs_7d": 150.0, "avg_fat_7d": 50.0, "avg_fiber_7d": 8.0, "avg_sugar_7d": 1.2, "avg_sat_fat_7d": 11.0, "trends": {"kcal": "flat", "protein": "flat", "carbs": "flat", "fat": "flat"}}
"""#

    private func nutritionProvider() -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k")
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    @Test func nutritionWeekDecodesCompleteDietQualityDay() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses[Self.nutritionDailyPath] = (200, Data(Self.nutritionDailyDQFixture.utf8))
        let days = try await nutritionProvider().nutritionWeek(windowDays: 3)
        #expect(days.count == 3)
        let d1 = try #require(days.first { $0.date == "2026-10-01" })
        #expect(d1.satFatG == 11.0)
        #expect(d1.coveragePct == 56.7)
        let dq = try #require(d1.dietQuality)
        #expect(dq.score == 80)
        #expect(dq.incomplete == false)
        #expect(dq.reason == nil)
        #expect(dq.coveragePct == 57)
        #expect(dq.formulaVersion == 1)
        #expect(dq.contributors.map(\.key) == ["fibre", "sugar", "sat_fat", "protein"])
        #expect(dq.contributors.first?.score == 38.1)
        #expect(dq.contributors.allSatisfy { $0.weight == 0.25 })
    }

    @Test func nutritionWeekDecodesIncompleteDayWithNAContributors() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses[Self.nutritionDailyPath] = (200, Data(Self.nutritionDailyDQFixture.utf8))
        let days = try await nutritionProvider().nutritionWeek(windowDays: 3)
        let d2 = try #require(days.first { $0.date == "2026-10-02" })
        let dq = try #require(d2.dietQuality)
        #expect(dq.score == nil)
        #expect(dq.incomplete)
        #expect(dq.reason == "few_meals")
        #expect(dq.coveragePct == 0)
        let fibre = try #require(dq.contributors.first { $0.key == "fibre" })
        #expect(fibre.score == nil && fibre.weight == nil)   // n/a, never 0
    }

    @Test func nutritionWeekToleratesOldHubWithoutDietQuality() async throws {
        StubURLProtocol.reset()
        let old = #"{"days":[{"date":"2026-10-01","kcal_consumed":1500,"meals_logged":3,"fiber_g":8}],"trends":{}}"#
        StubURLProtocol.responses[Self.nutritionDailyPath] = (200, Data(old.utf8))
        let days = try await nutritionProvider().nutritionWeek()
        #expect(days.count == 1)
        #expect(days[0].dietQuality == nil)
        #expect(days[0].satFatG == nil && days[0].coveragePct == nil)
    }
}
