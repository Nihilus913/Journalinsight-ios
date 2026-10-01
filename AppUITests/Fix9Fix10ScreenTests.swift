import XCTest

/// W-UITEST UT-3: the FIX9 / FIX10 / B49B screens, tap-proven. Data seeded by `fixture-hub.sh`:
/// today's gate answered automatically (GATED from Easy Run) and today's Apple workout with the
/// Watch's zone bounds <117 / 117–139 / 139–160 / 160–176 / 176+.
final class Fix9Fix10ScreenTests: JIUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        launch()
        passGate()
    }

    /// F10-1: Goals setup saves through the targets document (PUT /planning/targets), never the
    /// retired PUT /planning/goals (a 405 replayed from the outbox forever).
    func testF10_1_goalsSetupSavesTargetsNo405() throws {
        let before = try weightTarget()
        tab("More")
        tapId("more.nutrition")
        tapId("macro-edit-goals")
        let stepper = el("goals-setup-weight-target")
        reveal(stepper, "weight target stepper")
        tap(stepper.buttons["Increment"].firstMatch, "weight target +")
        tapId("goals-setup-save")
        var after = before
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, after == before { sleep(1); after = try weightTarget() }
        XCTAssertEqual(after, before + 0.5, "targets.goals.weight.target_kg after the save")
        XCTAssertFalse(el("goals-setup-hub-pending").exists, "the save stayed queued (outbox) instead of reaching the hub")
        if let log = ProcessInfo.processInfo.environment["UITEST_HUB_LOG"],
           let text = try? String(contentsOfFile: log, encoding: .utf8) {
            XCTAssertFalse(text.contains("\" 405"), "a 405 in the hub log (a retired route was written)")
        }
        shot("F10-1-goals-setup-saved-to-targets")
    }

    /// FIX9-1: the completed workout's zone bar labels carry the Watch's own bounds.
    func testFIX9_1_zoneBoundsOnCompletedWorkout() {
        tab("Training")
        XCTAssertTrue(el("training-hero").waitForExistence(timeout: 20))
        tapId("training-week-day-\(Self.todayWeekday)")
        let zones = el("completed-workout-zones")
        reveal(zones, "completed workout zone bar", timeout: 20)
        for label in ["Z1 <117 · 5 min", "Z2 117–139 · 10 min", "Z3 139–160 · 15 min", "Z4 160–176 · 2 min", "Z5 176+ · 1 min"] {
            XCTAssertTrue(zones.label.contains(label), "zone bar \(zones.label) lacks \(label)")
        }
        shot("FIX9-1-zone-bounds")
    }

    /// B49B G-3: Today shows "Answered automatically · GATED from Easy Run" for the hub's auto answer.
    func testG3_answeredAutomaticallyLine() {
        tab("Today")
        let line = el("today.gateRespond.auto")
        reveal(line, "G-3 answered-automatically line", timeout: 30)
        XCTAssertEqual(line.label, "Answered automatically · GATED from Easy Run")
        shot("G3-answered-automatically")
    }

    /// Monday = 0 … Sunday = 6 (the Training week strip's weekday).
    static var todayWeekday: Int {
        (Calendar(identifier: .gregorian).component(.weekday, from: Date()) + 5) % 7
    }

    private func weightTarget() throws -> Double {
        let doc = try hubGet("/api/v1/planning/targets") as? [String: Any]
        let weight = (doc?["goals"] as? [String: Any])?["weight"] as? [String: Any]
        return (weight?["target_kg"] as? NSNumber)?.doubleValue ?? -1
    }
}
