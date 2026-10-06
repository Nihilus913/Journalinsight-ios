import XCTest

/// W-FIX-P3 lane l5 sim proof (fixture hub): RG-82 HRV detail (card body opens it, 7 D, table),
/// RG-86 Mind "Today" card names the saved mood, RG-79 / RG-75 About & version (2.2.1 entry,
/// build number, Last crash note). Shots go to UITEST_SHOTS and the .xcresult.
final class FixP3L5Shots: JIUITestCase {
    private func launchPlain() {
        app = XCUIApplication()
        app.launchArguments = ["-hub-url", hubURL, "-hub-token", hubToken, "-no-healthkit", "-no-onboarding",
                               "-no-push", "-ui-testing"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 20)
        sleep(3)
    }

    private func text(_ s: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    func testRG82_hrvCardBodyOpensDetail() {
        launchPlain()
        tab("Recovery")
        let chart = el("recovery.chart.hrv")
        reveal(chart, "Recovery HRV chart", timeout: 30)
        shot("rg82-1-recovery-hrv-card")
        chart.tap()   // the card body, not the title row
        reveal(el("kpi-detail-chart"), "HRV detail opened from the card body", timeout: 20)
        app.buttons["7 D"].firstMatch.tap()
        sleep(2)
        shot("rg82-2-hrv-detail-7d")
        let legend = el("kpi-detail-legend")
        XCTAssertFalse(legend.label.contains("dashed = median"), "legend: \(legend.label)")
        app.swipeUp()
        sleep(1)
        shot("rg82-3-hrv-detail-table")
    }

    func testRG86_mindTodayShowsSavedMood() {
        launchPlain()
        sleep(5)
        tab("More")
        tapId("more.mind")
        sleep(3)
        let open = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'mind-' AND identifier ENDSWITH '-checkin'")).firstMatch
        tap(open, "check-in button")
        sleep(2)
        shot("rg86-0-checkin-sheet")
        let good = app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH 'Good'")).firstMatch
        tap(good, "Good mood row")
        tapId("checkin-save")
        sleep(2)
        let mood = el("mind-today-mood")
        reveal(mood, "Today card mood word", timeout: 20)
        XCTAssertTrue(mood.label.contains("Good"), "mood: \(mood.label)")
        shot("rg86-mind-today-mood-word")
    }

    func testRG79_aboutVersion() {
        launchPlain()
        tab("More")
        tapId("more.settings")
        sleep(2)
        let about = app.buttons["About & version"].firstMatch
        tap(about, "About & version row")
        sleep(2)
        reveal(text("2.2.1"), "2.2.1 entry / version line", timeout: 20)
        shot("rg79-1-about-version")
        let footer = text("Swift crashes")
        reveal(footer, "Last crash note (Swift traps via MetricKit)")
        shot("rg75-2-last-crash-note")
    }
}
