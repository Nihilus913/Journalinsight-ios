import XCTest

/// B-43 P3 (close-out proof): a rest-end alert reaches the home screen while the app is in the
/// background, and tapping it deep-links back into the set logger (`ji://strength-log`).
///
/// Opt-in — it waits out the logger's full 90 s rest:
/// `JI_B43_PROOF=1 bash AppUITests/fixture-hub.sh test -only-testing:AppUITests/B43RestAlertUITests`
/// (the fixture hub passes the env through as `TEST_RUNNER_JI_B43_PROOF`).
///
/// Flow: Decide → Go · Training › Planner › Day 1 › Log sets · allow the notification prompt the
/// logger raises · log one set (rest starts) · home · wait · springboard shows "Rest over 💪" ·
/// tap it · the logger is in front again.
final class B43RestAlertUITests: JIUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["JI_B43_PROOF"] == "1", "opt-in (JI_B43_PROOF=1)")
        launch()
        passGate()
        tab("Training")
        XCTAssertTrue(el("training-hero").waitForExistence(timeout: 20))
    }

    func testRestEndAlertShowsWhileBackgroundedAndOpensTheLogger() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        // Training › Planner › Day 1 › Log sets (the PL-5 path).
        tapId("training-open-planner")
        XCTAssertTrue(el("workouts-list").waitForExistence(timeout: 15), "Planner did not open")
        let post073 = element(idPrefix: "workouts-row-", labelContains: "Day 1")
        let day1 = post073.waitForExistence(timeout: 10) ? post073 : element(idPrefix: "planner-row-s", labelContains: "Day 1")
        reveal(day1, "Planner row Day 1")
        tap(day1, "Planner row Day 1")
        XCTAssertTrue(el("planner-strength-detail").waitForExistence(timeout: 10), "Day 1 detail did not open")
        let logSets = el("planner-log-sets")
        reveal(logSets, "Day 1 Log sets")
        tap(logSets, "Log sets")
        reveal(el("strength-log-add-exercise"), "the set logger after Log sets")

        // B-43 P1: opening the logger asks for notification permission — allow it.
        let allow = springboard.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 8) { allow.tap() }

        // Log the first set of the first lift: the 90 s rest countdown starts.
        let logSet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'strength-log-set-'")).firstMatch
        reveal(logSet, "a Log set button")
        tap(logSet, "Log set")
        XCTAssertTrue(el("strength-rest-timer").waitForExistence(timeout: 10), "rest countdown did not start")
        shot("B43-1-rest-running")

        // Background the app and wait for the rest to end (+ a margin for delivery).
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
        sleep(100)
        let banner = springboard.staticTexts["Rest over 💪"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "no 'Rest over' notification on the home screen")
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let att = XCTAttachment(uniformTypeIdentifier: "public.png", name: "B43-2-rest-over-banner.png", payload: png, userInfo: nil)
        att.lifetime = .keepAlways
        add(att)
        if let dir = shotsDir {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("B43-2-rest-over-banner.png"))
        }

        // Tap → `ji://strength-log` → the logger is in front again (the held one, countdown gone).
        banner.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "the tap did not open the app")
        XCTAssertTrue(el("strength-log-add-exercise").waitForExistence(timeout: 15), "the tap did not land in the set logger")
        shot("B43-3-logger-after-tap")
    }
}
