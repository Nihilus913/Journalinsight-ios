import XCTest

/// W-FIX-P3 lane l3 sim proof (RG-61 / 62 / 63 / 66 / 67 / 68): Training screens against a
/// throwaway hub (own pg_dump). Best effort per screen — a screen that does not open is dumped,
/// the next one still runs. `UITEST_SHOTS` = the proof PNG dir.
final class FixP3L3Shots: JIUITestCase {
    private func back() {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.exists { b.tap() }
    }

    private func open(_ id: String, wait: String, shot name: String) -> Bool {
        let e = el(id)
        guard e.waitForExistence(timeout: 15) else { dump(id); return false }
        e.tap()
        guard el(wait).waitForExistence(timeout: 20) else { dump(wait); shot(name + "-miss"); return false }
        sleep(2)
        shot(name)
        return true
    }

    func testTrainingScreens() {
        // No forced gate (its Go write does not clear on a pg_dump of today's prod state).
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = Array(Self.launchArguments(hubURL: hubURL, hubToken: hubToken).dropFirst(2))
        app.launch()
        if declineHealthAccessSheet() { app.terminate(); app.launch() }
        tab("Training")
        _ = el("training-hero").waitForExistence(timeout: 20)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let dontAllow = springboard.buttons["Don’t Allow"].firstMatch
        if dontAllow.waitForExistence(timeout: 3) { dontAllow.tap() }
        shot("l3-training")

        // RG-62 Time in zone (default W, scope picker, 5 floors)
        if open("training-zone-time", wait: "zone-time-range", shot: "rg62-zone-W") {
            if el("zone-time-scope").exists { app.segmentedControls["zone-time-scope"].buttons["All workouts"].tap(); sleep(3); shot("rg62-zone-W-all") }
            back()
        }
        // RG-63 Progress (no D on strength cards)
        if open("training-progress", wait: "progress.screen", shot: "rg63-progress") {
            app.swipeUp(); sleep(1); shot("rg63-progress-2")
            back()
        }
        // RG-68 Send to Watch rows
        if open("training-send-to-watch", wait: "send-to-watch-close", shot: "rg68-send-to-watch") {
            el("send-to-watch-close").tap()
        }
        // RG-66 Planner Week, Month; RG-66/67 logger; RG-61 History, Records
        if open("training-open-planner", wait: "workouts-list", shot: "rg66-planner-week") {
            let scope = el("planner-scope")
            if scope.exists, app.segmentedControls["planner-scope"].buttons["Month"].exists {
                app.segmentedControls["planner-scope"].buttons["Month"].tap(); sleep(3); shot("rg66-planner-month")
                app.swipeUp(); sleep(1); shot("rg66-planner-month-legend")
                app.swipeDown(); app.segmentedControls["planner-scope"].buttons.element(boundBy: 0).tap(); sleep(1)
            }
            let day1 = element(idPrefix: "workouts-row-", labelContains: "Day 1")
            if day1.waitForExistence(timeout: 10) {
                day1.tap()
                if el("planner-log-sets").waitForExistence(timeout: 10) {
                    el("planner-log-sets").tap()
                    if el("strength-log-add-exercise").waitForExistence(timeout: 20) {
                        if dontAllow.waitForExistence(timeout: 5) { dontAllow.tap() }
                        sleep(2); shot("rg66-rg67-logger")
                        app.swipeUp(); sleep(1); shot("rg67-logger-2")
                        if el("strength-log-history").exists {
                            el("strength-log-history").tap(); sleep(4); shot("rg61-history")
                            app.swipeUp(); app.swipeUp(); sleep(1); shot("rg61-history-garmin")
                            back()
                        }
                        if el("strength-log-records").waitForExistence(timeout: 5) {
                            el("strength-log-records").tap(); sleep(4); shot("rg61-records")
                            app.swipeUp(); sleep(1); shot("rg61-records-2")
                        }
                    }
                }
            }
        }
    }
}
