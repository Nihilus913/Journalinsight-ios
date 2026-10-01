import XCTest

/// W-UITEST UT-3: the FIX9 / FIX10 / B49B screens, tap-proven. Data seeded by `fixture-hub.sh`:
/// today's gate answered automatically (GATED from Easy Run) and today's Apple workout with the
/// Watch's zone bounds <117 / 117–139 / 139–160 / 160–176 / 176+.
final class Fix9Fix10ScreenTests: JIUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        launch()
    }

    /// F10-1: the Goals edit saves through the targets document (PUT /planning/targets), never the
    /// retired PUT /planning/goals (a 405 replayed from the outbox forever). Since W-TGT L3 the
    /// app's Goals entry is More › Goals › Edit (the Targets editor on the weight goal); the old
    /// Goals setup screen has no entry any more.
    func testF10_1_goalsSetupSavesTargetsNo405() throws {
        passGate()
        let before = try weightTarget()
        tab("More")
        tapId("more.goals")
        tapId("goals-edit-targets")
        tapId("targetEditor.goal.increase")
        // The editor starts from the phone's own targets copy (which can be ahead of a fresh fixture
        // hub): the hub must end up with exactly what the field shows after the +0.5 step.
        let field = el("targetEditor.goal.field")
        let shown = Double(((field.value as? String) ?? "").replacingOccurrences(of: ",", with: ".")) ?? -2
        tapId("targetEditor.save")
        XCTAssertTrue(el("targetEditor.save").waitForNonExistence(timeout: 15), "the Targets editor stayed open after Save")
        var after = before
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, after == before { sleep(1); after = try weightTarget() }
        XCTAssertNotEqual(after, before, "targets.goals.weight.target_kg never changed on the hub")
        XCTAssertEqual(after, shown, "targets.goals.weight.target_kg after the save (the field showed \(shown))")
        if let log = ProcessInfo.processInfo.environment["UITEST_HUB_LOG"],
           let text = try? String(contentsOfFile: log, encoding: .utf8) {
            XCTAssertFalse(text.contains("\" 405"), "a 405 in the hub log (a retired route was written)")
            XCTAssertFalse(text.contains("PUT /api/v1/planning/goals"), "the retired PUT /planning/goals was written")
            XCTAssertTrue(text.contains("PUT /api/v1/planning/targets"), "no PUT /planning/targets reached the hub")
        }
        shot("F10-1-goals-setup-saved-to-targets")
    }

    /// FIX9-1: the completed workout's zone bar labels carry the Watch's own bounds.
    func testFIX9_1_zoneBoundsOnCompletedWorkout() {
        passGate()
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

    /// B49B G-3: the hub's automatic answer shows as "Answered automatically · GATED from Easy Run".
    /// Since W-B57b the weekly gate answer lives at the bottom of the gate rationale; Decide's
    /// "Why" rows open it — the first screen of the day, before Go.
    func testG3_answeredAutomaticallyLine() {
        let expected = "Answered automatically · GATED from Easy Run"
        if !awaitDecide() { dump("G-3-Decide") }
        XCTAssertTrue(app.buttons["today.decide.go"].exists, "-JIForceGate YES did not open Decide")
        let signal = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'today.decide.signal.'")).firstMatch
        tap(signal, "Decide signal row")
        XCTAssertTrue(el("gateRationale.caption").waitForExistence(timeout: 15), "the signal row did not open the gate rationale")
        // The card's container id ("gateRationale.weeklyRespond") is stamped on its children.
        let line = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Answered automatically'")).firstMatch
        reveal(line, "rationale 'Answered automatically' line", timeout: 15)
        XCTAssertEqual(line.label, expected)
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
