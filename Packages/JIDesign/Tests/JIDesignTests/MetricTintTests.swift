import Testing
@testable import JIDesign

// B-47 — the metric → colour-role map L2's Today grid tints its cards with.
@Test(arguments: [
    ("hrv", JIColorRole.hrv),
    ("rhr", .rhr), ("Resting HR", .rhr), ("resting_hr", .rhr),
    ("sleep", .sleep), ("sleep_score", .sleep), ("Sleep score", .sleep),
    ("steps", .steps),
    ("load", .load), ("acwr", .load), ("Load (ACWR)", .load),
    // B-57 W1 r5: the macro colours the Monitor / Plan boards tint with.
    ("kcal", .kcal), ("Calories", .kcal),
    ("protein", .protein), ("Protein", .protein),
    ("carbs", .carbs), ("Carbohydrates", .carbs),
    ("fat", .fat), ("Fat", .fat),
])
func theContractMetricsCarryTheirOwnRole(id: String, role: JIColorRole) {
    #expect(metricTintRole(id) == role)
}

@Test(arguments: ["weight", "body_battery", "readiness", "fibre", "sugar", "", "not_a_metric"])
func everythingElseIsPrimaryText(id: String) {
    #expect(metricTintRole(id) == .text)
}

/// Case and separators never change the answer — a wire id and a display label must land on the
/// same colour, or the same metric reads in two colours on two screens.
@Test func theLookupIsCaseAndSeparatorInsensitive() {
    #expect(metricTintRole("HRV") == metricTintRole("hrv"))
    #expect(metricTintRole("  Steps ") == .steps)
    #expect(metricTintRole("SLEEP SCORE") == .sleep)
}

/// Rule 6: the reserved verdict roles are only ever handed out by this map, never invented per
/// card — and no metric gets a surface/hairline role by mistake.
@Test func onlyForegroundRolesAreEverReturned() {
    let allowed: Set<JIColorRole> = [.hrv, .rhr, .sleep, .steps, .load, .text, .kcal, .protein, .carbs, .fat]
    for id in ["hrv", "rhr", "sleep", "steps", "load", "acwr", "weight", "kcal", "protein", "carbs", "fat", "zzz"] {
        #expect(allowed.contains(metricTintRole(id)))
    }
}

/// B-57 W1 r5: the four macro roles are distinct from each other and from the verdict roles —
/// calories are a metric colour, never "Modified".
@Test func macroRolesAreTheirOwnRoles() {
    let macros: [JIColorRole] = [.kcal, .protein, .carbs, .fat]
    #expect(Set(macros).count == 4)
    #expect(Set(macros).isDisjoint(with: [.go, .reduced, .danger, .info, .sleep, .text]))
    #expect(macros.allSatisfy { JIColorRole.macroRoles.contains($0) })
}

/// W-GUI F4 (report §4.3): the verdict roles never tint a metric numeral; steps earn `.go`
/// only against a user goal.
@Test func metricsNeverWearTheVerdictRoles() {
    for id in ["hrv", "rhr", "sleep", "steps", "load", "acwr", "weight", "kcal", "protein", "carbs", "fat"] {
        #expect(![JIColorRole.go, .reduced, .danger, .info].contains(metricTintRole(id)), Comment(rawValue: id))
    }
    #expect(metricTintRole("steps", hasGoal: true) == .go)
    #expect(metricTintRole("steps", hasGoal: false) == .steps)
    #expect(metricTintRole("rhr", hasGoal: true) == .rhr)
}
