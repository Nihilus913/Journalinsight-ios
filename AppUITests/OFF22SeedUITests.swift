import XCTest

/// W-OFFLINE2 OFF2-2 sim exit check: on an ERASED clone with NO hub, launch with
/// `-seed-healthkit-fixture`, allow the Health Access sheet (the seed's share+read request), then
/// relaunch with the flag — the second run must write nothing (read the counts with
/// `xcrun simctl spawn <udid> log show --predicate 'category == "JIDebugSeed"'`).
/// Opt-in: `TEST_RUNNER_JI_OFF22_SEED=1 xcodebuild test -scheme AppUITests ... -only-testing:AppUITests/OFF22SeedUITests`.
final class OFF22SeedUITests: JIUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["JI_OFF22_SEED"] == "1", "opt-in (JI_OFF22_SEED=1)")
    }

    /// Health Access sheet: turn every topic on, then Allow. False when no sheet showed.
    private func allowHealthSheet(timeout: TimeInterval) -> Bool {
        let all = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Select All' OR label BEGINSWITH 'Turn On All'")).firstMatch
        guard all.waitForExistence(timeout: timeout) else { return false }
        all.tap()
        let allow = app.buttons.matching(NSPredicate(format: "label == 'Allow'")).firstMatch
        var n = 0
        while !(allow.exists && allow.isEnabled && allow.isHittable) && n < 12 { app.swipeUp(); n += 1 }
        guard allow.exists else { dump("Health Access sheet (no Allow)"); return false }
        allow.tap()
        return all.waitForNonExistence(timeout: 10)
    }

    private func launchNoHub() {
        app = XCUIApplication()
        app.launchArguments = ["-seed-healthkit-fixture", "-no-onboarding", "-no-push", "-ui-testing"]
        app.launch()
    }

    func testSeedOnErasedNoHubClone() {
        launchNoHub()
        var sheets = 0
        while allowHealthSheet(timeout: sheets == 0 ? 30 : 8) && sheets < 3 { sheets += 1 }
        sleep(8)   // the seed's save + read-back count
        shot("off2-2-after-seed")
        app.terminate()
        launchNoHub()
        _ = allowHealthSheet(timeout: 8)
        sleep(6)
        shot("off2-2-second-launch")
        print("[OFF22-SEED] health sheets allowed: \(sheets)")
        XCTAssertGreaterThan(sheets, 0, "no Health Access sheet — the seed never asked")
    }
}
