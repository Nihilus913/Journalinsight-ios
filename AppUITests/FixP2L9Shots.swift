import XCTest

/// W-FIX-P2 lane l9 proof shots (fixture hub on a prod clone, no HealthKit):
/// RG-42 Nutrition 0-meal day + Energy balance keep their titles, no stuck skeleton;
/// RG-43 Nutrition 7-days-vs-goal draws seven slots + the ±5 % band;
/// RG-46 Energy burn card falls back to the hub's tdee_raw (Health has no burn on the sim);
/// RG-50 My KPIs Readiness names the watch source + date; RG-51 More Goals row 'start → goal' dated;
/// RG-52 Mind privacy copy.
final class FixP2L9Shots: JIUITestCase {
    private func launchPlain() {
        app = XCUIApplication()
        app.launchArguments = ["-hub-url", hubURL, "-hub-token", hubToken, "-no-healthkit", "-no-onboarding",
                               "-no-push", "-ui-testing"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 20)
        sleep(3)
    }

    private func contains(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testRG42_RG43_nutritionZeroMealDayAndWeekSlots() {
        launchPlain()
        tab("More")
        tapId("more.nutrition")
        sleep(3)
        shot("rg42-nutrition-0-meal-day")
        let bars = el("nutrition-week-bars")
        reveal(bars, "Nutrition 7 days vs goal", timeout: 20)
        shot("rg43-nutrition-week-7-slots-band")
        XCTAssertFalse(contains("—").exists && app.staticTexts.count < 3, "nutrition rendered a bare skeleton")
    }

    func testRG42_RG46_energyBalanceAndBurnFallback() {
        launchPlain()
        tab("More")
        tapId("more.energy")
        sleep(3)
        let hero = el("energy.hero")
        reveal(hero, "Energy hero", timeout: 20)
        shot("rg42-energy-7-day-balance")
        let burn = el("energy.whatYouBurn")
        reveal(burn, "What you burn card", timeout: 20)
        shot("rg46-energy-burn-hub-tdee")
        let copy = contains("via the hub")
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "burn card did not use the hub copy")
    }

    func testRG50_RG51_kpisReadinessLabelAndWeightRow() {
        launchPlain()
        tab("More")
        tapId("more.kpis")
        sleep(3)
        let readiness = contains("Watch readiness")
        reveal(readiness, "Readiness square labelled 'Watch readiness'", timeout: 20)
        shot("rg50-kpi-list-watch-readiness")
        let weight = contains("79.5")
        reveal(weight, "Weight KPI newest row 79.5", timeout: 10)
        shot("rg51-kpi-weight-79-5")
    }

    func testRG51_moreGoalsRowStartToGoal() {
        launchPlain()
        tab("More")
        let row = contains("Start ")
        reveal(row, "More Goals row 'start → goal'", timeout: 20)
        shot("rg51-more-goals-start-to-goal")
        XCTAssertTrue(row.label.contains("goal"), "row: \(row.label)")
    }

    func testRG52_mindPrivacyCopy() {
        // Mirror OFF: "Everything stays on your device."
        launchPlain()
        tab("More")
        tapId("more.mind")
        sleep(3)
        let footer = el("mind-privacy-footer")
        reveal(footer, "Mind privacy footer (mirror off)", timeout: 20)
        XCTAssertTrue(footer.label.contains("Everything stays on your device"), "footer: \(footer.label)")
        shot("rg52-mind-privacy-mirror-off")
        // Mirror ON (Settings › Apple Health › Mirror mood): the copy names Apple Health.
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-hub-url", hubURL, "-hub-token", hubToken, "-no-healthkit", "-no-onboarding",
                               "-no-push", "-ui-testing", "-ji.mind.mirrorMoodToHealth", "YES"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 20)
        sleep(3)
        tab("More")
        tapId("more.mind")
        sleep(3)
        let footerOn = el("mind-privacy-footer")
        reveal(footerOn, "Mind privacy footer (mirror on)", timeout: 20)
        XCTAssertTrue(footerOn.label.contains("also written to Apple Health"), "footer: \(footerOn.label)")
        shot("rg52-mind-privacy-mirror-on")
    }
}
