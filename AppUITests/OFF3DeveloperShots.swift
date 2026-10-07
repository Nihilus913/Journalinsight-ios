import XCTest

/// W-OFFLINE OFF-3 (B-50 slice 1) proof shot: Settings › Developer › "Data source (debug)" on a
/// launch with NO hub config (no `-hub-url`/`-hub-token`, empty Keychain ConnectionConfig).
/// Debug build only — the Developer group is not compiled into Release (Toby 2026-10-04).
final class OFF3DeveloperShots: JIUITestCase {
    func testOFF3_developerDataSourceWithNoHub() {
        app = XCUIApplication()
        app.launchArguments = ["-no-onboarding", "-no-push", "-ui-testing"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 20)
        _ = declineHealthAccessSheet()
        tapId("root.settings")
        let dev = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Developer'")).firstMatch
        tap(dev, "Developer group")
        let active = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Active: '")).firstMatch
        reveal(active, "Active data source row")
        shot("off3-settings-developer-no-hub")
        XCTAssertTrue(active.label.contains("HealthTraining hub"), "default must be the hub: \(active.label)")
        XCTAssertTrue(app.switches.matching(NSPredicate(format: "label CONTAINS 'Read from Apple Watch'")).firstMatch.exists)
    }
}
