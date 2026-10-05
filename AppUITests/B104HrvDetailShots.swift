import XCTest

/// B-104 p2: the HRV KPI detail over a hub that sends `hrv_src` — Garmin nights dashed + "est."
/// beside Watch nights, the per-source "Nights counted" row; then, with the hub unreachable, the
/// same screen from the offline cache. Run against a prod-clone hub (UITEST_HUB_URL/TOKEN);
/// shots go to UITEST_SHOTS and the .xcresult.
final class B104HrvDetailShots: JIUITestCase {
    private func openHrvDetail() {
        XCUIDevice.shared.system.open(URL(string: "ji://kpi-detail?metric=hrv")!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let open = springboard.buttons["Open"]
        if open.waitForExistence(timeout: 5) { open.tap() }
        reveal(el("kpi-detail-chart"), "HRV chart", timeout: 30)
    }

    /// No forced gate here (its Go is the gate test's job): today's call already exists on the clone.
    private func launchPlain(hubURL: String) {
        app = XCUIApplication()
        app.launchArguments = ["-hub-url", hubURL, "-hub-token", hubToken, "-no-healthkit", "-no-onboarding", "-no-push", "-ui-testing"]
        app.launch()
        sleep(3)
    }

    func testB104_hrvDetailShowsGarminEstimates() {
        launchPlain(hubURL: hubURL)
        openHrvDetail()
        app.buttons["90 D"].firstMatch.tap()
        sleep(2)
        shot("b104p2-1-hrv-90d-hub-up")
        let legend = el("kpi-detail-legend")
        XCTAssertTrue(legend.label.contains("Garmin × 0.95 (est.)"), "legend: \(legend.label)")
        app.swipeUp()
        sleep(1)
        // The table card's combined element wins the identifier; find the row by its words.
        let sources = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Watch +'")).firstMatch
        reveal(sources, "Nights counted row")
        XCTAssertTrue(sources.label.contains("Watch +"), "sources row: \(sources.label)")
        shot("b104p2-2-hrv-90d-table")
        // Hub down: a dead port — the screen renders from the cache.
        app.terminate()
        launchPlain(hubURL: "http://127.0.0.1:8798")
        openHrvDetail()
        app.buttons["90 D"].firstMatch.tap()
        sleep(2)
        shot("b104p2-3-hrv-90d-hub-down-cache")
        XCTAssertTrue(el("kpi-detail-legend").label.contains("est."), "offline legend lost the Garmin style")
    }
}
