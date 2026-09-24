import SwiftUI
import Testing
import JIDesign
@testable import JIFeatures

struct B57ShellTests {
    @Test func energyExplainerIsTheFourBoardSteps() {
        #expect(JIExplainers.energyBalanceSteps.map(\.title) == [
            "Burned = resting + active energy",
            "Eaten = dietary energy in Apple Health",
            "Balance = eaten − burned, 7-day average",
            "Deficit or surplus",
        ])
        #expect(JIExplainers.energyBalanceNote.contains("no medical judgement"))
        #expect(JIExplainers.nutritionSourceLabel == "YAZIO via Apple Health")
    }

    @Test @MainActor func shellHooksDefaultToNil() {
        let env = EnvironmentValues()
        #expect(env.openKpiCatalogue == nil)
        #expect(env.openKpiDetail == nil)
    }

    @Test func registryCarriesTheW1ScreensAndNoChallenges() {
        let names = ScreenRegistry.entries.map(\.name)
        for n in ["Trends", "Meal detail", "KPI detail nutrition"] { #expect(names.contains(n)) }
        for n in ["Trends card", "Nutrition log", "Challenges", "Challenge editor"] { #expect(!names.contains(n)) }
    }
}
