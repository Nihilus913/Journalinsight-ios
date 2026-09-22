import Testing
@testable import JIDesign

// B-47 — the metric → colour-role map L2's Today grid tints its cards with.
@Test(arguments: [
    ("hrv", JIColorRole.info),
    ("rhr", .danger), ("Resting HR", .danger), ("resting_hr", .danger),
    ("sleep", .sleep), ("sleep_score", .sleep), ("Sleep score", .sleep),
    ("steps", .go),
    ("load", .reduced), ("acwr", .reduced), ("Load (ACWR)", .reduced),
])
func theContractMetricsCarryTheirOwnRole(id: String, role: JIColorRole) {
    #expect(metricTintRole(id) == role)
}

@Test(arguments: ["weight", "body_battery", "readiness", "kcal", "protein", "carbs", "fat", "", "not_a_metric"])
func everythingElseIsPrimaryText(id: String) {
    #expect(metricTintRole(id) == .text)
}

/// Case and separators never change the answer — a wire id and a display label must land on the
/// same colour, or the same metric reads in two colours on two screens.
@Test func theLookupIsCaseAndSeparatorInsensitive() {
    #expect(metricTintRole("HRV") == metricTintRole("hrv"))
    #expect(metricTintRole("  Steps ") == .go)
    #expect(metricTintRole("SLEEP SCORE") == .sleep)
}

/// Rule 6: the reserved verdict roles are only ever handed out by this map, never invented per
/// card — and no metric gets a surface/hairline role by mistake.
@Test func onlyForegroundRolesAreEverReturned() {
    let allowed: Set<JIColorRole> = [.info, .danger, .sleep, .go, .reduced, .text]
    for id in ["hrv", "rhr", "sleep", "steps", "load", "acwr", "weight", "kcal", "zzz"] {
        #expect(allowed.contains(metricTintRole(id)))
    }
}
