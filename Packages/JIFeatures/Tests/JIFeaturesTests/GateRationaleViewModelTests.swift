import Foundation
import Testing
import JICore
@testable import JIFeatures

/// Port of the oracle `mobile/__tests__/gateRationale/gateRationaleScreen.render.test.tsx` at the
/// view-model level: the screen's every rendered string is a pure derivation here, so the cases
/// assert the same copy without a rendering harness.
private let en = Locale(identifier: "en_US")

/// Serves the hub-contract fixtures, with the gate's decision fields overridable — the oracle's
/// `fakeProvider({...gateOverrides})`. `morningVerdict` can be made to 404 for the deep-link branch.
private struct GateRationaleProvider: HealthDataProvider {
    let capabilities: DataCapability = .hubAll
    private let inner = MockDataProvider()
    var recommendation: GateRecommendation = .reduce
    var triggeredRules: [String] = []
    var suggestions: [String] = []
    var trackedDays = 6, totalDays = 7, minTrackedDays = 4
    var recoveryDays: [RecoveryDay]?
    var verdictError: (any Error)?
    var liveError: (any Error)?

    func health() async throws -> HealthResponse { try await inner.health() }
    func gate(windowDays: Int) async throws -> GateResponse {
        if let liveError { throw liveError }
        var g = try await inner.gate(windowDays: windowDays)
        g.recommendation = recommendation
        g.triggeredRules = triggeredRules
        g.suggestions = suggestions
        g.trackedDays = trackedDays; g.totalDays = totalDays; g.minTrackedDays = minTrackedDays
        return g
    }
    func morning() async throws -> MorningResponse {
        if let liveError { throw liveError }
        return try await inner.morning()
    }
    func morningVerdict(date: String) async throws -> MorningVerdict {
        if let verdictError { throw verdictError }
        return try await inner.morningVerdict(date: date)
    }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] {
        if let liveError { throw liveError }
        if let recoveryDays { return recoveryDays }
        return try await inner.recovery(windowDays: windowDays)
    }
    func syncStatus() async throws -> SyncStatus { try await inner.syncStatus() }
}

// MARK: - The live branch

@Test @MainActor func rendersHumanizedRulesSuggestionsAndTheThreeDayTrail() async throws {
    var p = GateRationaleProvider()
    p.recommendation = .reduce
    p.triggeredRules = ["avg_protein_7d 118.0 vs threshold 130.0 (REDUCE: insufficient protein)"]
    p.suggestions = ["Front-load protein earlier in the day"]
    let vm = GateRationaleViewModel(provider: p)
    await vm.load()

    #expect(vm.phase == .loaded)
    #expect(vm.humanizedRules(locale: en)
            == ["7-day protein averages 118g against the 130g floor — insufficient protein."])
    // The raw debug string must never reach the screen.
    #expect(vm.humanizedRules(locale: en).allSatisfy { !$0.contains("avg_protein_7d") })
    #expect(vm.suggestionLines == ["Front-load protein earlier in the day"])
    #expect(vm.suggestionsEmptyCopy == nil)
    #expect(vm.recommendationLabel == "Gate recommends REDUCE")
    #expect(vm.trailDays.count == 3)
    #expect(vm.trailDays.contains { $0.metricsLine(locale: en).contains("RHR") })
    #expect(vm.verdict.word == "GO")
    // B-57 W1 r5: the header shows Decide's user-facing word, never the hub's GO.
    #expect(vm.verdictWord == "Full")
}

@Test @MainActor func anEmptyGateShowsTheCleanDayCopyNotABlankSection() async throws {
    var p = GateRationaleProvider()
    p.recommendation = .progress
    let vm = GateRationaleViewModel(provider: p)
    await vm.load()

    #expect(vm.noRulesCopy == "No rules triggered — a clean day against every threshold.")
    #expect(vm.suggestionLines.isEmpty)
    #expect(vm.suggestionsEmptyCopy == "No specific suggestions right now.")
    #expect(vm.recommendationLabel == "Gate recommends PROGRESS")
}

/// HT's `evaluate_kpi_gates()` returns `suggestions=[]` for BOTH its REDUCE and MAINTAIN branches
/// whenever a rule fires — a triggered rule with no suggestions is the normal case, so the clean-day
/// copy must never sit under one.
@Test @MainActor func aTriggeredRuleWithNoSuggestionsShowsTheDerivedAction() async throws {
    var p = GateRationaleProvider()
    p.triggeredRules = ["avg_kcal_7d 1235.8 vs threshold 1600.0 (REDUCE: chronic underfueling (5+ of 7 days))"]
    p.suggestions = []
    let vm = GateRationaleViewModel(provider: p)
    await vm.load()

    #expect(vm.suggestionsEmptyCopy == nil)
    #expect(vm.suggestionLines == ["Bring kcal back up toward goal — this is chronic under-fueling, not a plateau."])
    #expect(vm.noRulesCopy == nil)
}

@Test @MainActor func insufficientDataCarriesTheHonestCountsAndNothingElseDoes() async throws {
    var p = GateRationaleProvider()
    p.recommendation = .insufficientData
    p.trackedDays = 1; p.totalDays = 8; p.minTrackedDays = 4
    let vm = GateRationaleViewModel(provider: p)
    await vm.load()
    #expect(vm.recommendationLabel == "Not enough tracked days yet for a recommendation")
    #expect(vm.trackedDaysLine == "1 of 8 days tracked · needs 4")

    var q = GateRationaleProvider()
    q.recommendation = .reduce
    q.trackedDays = 6; q.totalDays = 7; q.minTrackedDays = 4
    let vm2 = GateRationaleViewModel(provider: q)
    await vm2.load()
    #expect(vm2.recommendationLabel == "Gate recommends REDUCE")
    #expect(vm2.trackedDaysLine == nil)
}

@Test @MainActor func theTrailIsTheThreeNewestDaysOldestFirstWithHrvJoinedByDate() async throws {
    let vm = GateRationaleViewModel(provider: GateRationaleProvider())
    await vm.load()
    let dates = vm.trailDays.map(\.date)
    #expect(dates == ["2026-09-09", "2026-09-10", "2026-09-11"])
    // readiness 64 / 89 / 77 -> amber / go / go (Garmin's own score, bucketed only to colour the dot)
    #expect(vm.trailDays.map(\.tone) == [.amber, .go, .go])
}

@Test @MainActor func anEmptyRecoveryHistoryYieldsNoTrailRatherThanZeroedColumns() async throws {
    var p = GateRationaleProvider()
    p.recoveryDays = []
    let vm = GateRationaleViewModel(provider: p)
    await vm.load()
    #expect(vm.trailDays.isEmpty)
}

@Test @MainActor func aDayWithNoneOfTheThreeMetricsRendersAnEmDashNeverAZero() async throws {
    var p = GateRationaleProvider()
    p.recoveryDays = [RecoveryDay(date: "2099-01-01")]
    let vm = GateRationaleViewModel(provider: p)
    await vm.load()
    #expect(vm.trailDays.map { $0.metricsLine(locale: en) } == ["—"])
    #expect(vm.trailDays.map(\.tone) == [.muted])
}

@Test @MainActor func hubFailureOnAFirstLoadIsAnErrorPhaseWithNamedCopy() async throws {
    var p = GateRationaleProvider()
    p.liveError = HubError.network("simulated")
    let vm = GateRationaleViewModel(provider: p)
    await vm.load()
    #expect(vm.phase == .error("Hub unreachable — is the Mac awake and on the same network?"))
    #expect(vm.lastError == .network("simulated"))
}

@Test @MainActor func anAlreadyLoadedScreenKeepsItsRationaleWhenARefreshFails() async throws {
    let vm = GateRationaleViewModel(provider: GateRationaleProvider())
    await vm.load()
    #expect(vm.phase == .loaded)

    var failing = GateRationaleProvider()
    failing.liveError = HubError.network("simulated")
    let vm2 = GateRationaleViewModel(provider: failing)
    await vm2.load()
    #expect(vm2.gate == nil)          // nothing held -> honest error, not a blank "loaded"
    #expect(vm2.phase != .loaded)
}

// MARK: - The deep-link per-date branch

@Test @MainActor func theByDateBranchReadsThePersistedRowAndShowsLess() async throws {
    let vm = GateRationaleViewModel(provider: GateRationaleProvider(), date: "2026-09-11")
    await vm.load()
    #expect(vm.isByDate)
    #expect(vm.phase == .loaded)
    #expect(vm.verdict.word == "GO (auto-regulated)")
    #expect(vm.verdictWord == "Modified")   // W-FIX1 BUG-03
    #expect(vm.verdictForDate?.reason?.hasPrefix("Amber (HRV 23, RHR 66)") == true)
    // The rich live-only sections have nothing to draw from.
    #expect(vm.gate == nil)
    #expect(vm.trailDays.isEmpty)
    // Prefix only: ICU joins the AM marker with U+202F (narrow no-break space), which is not a
    // stable byte to pin; the hour/minute in the hub's own offset is the contract.
    #expect(vm.computedAtTime(locale: en, timeZone: TimeZone(identifier: "Europe/Zurich")!)?.hasPrefix("06:00") == true)
}

@Test @MainActor func a404OnTheByDateBranchIsTheBenignNoVerdictCopyNotAnError() async throws {
    var p = GateRationaleProvider()
    p.verdictError = HubError.http(status: 404, detail: nil)
    let vm = GateRationaleViewModel(provider: p, date: "2026-01-02")
    await vm.load()
    #expect(vm.phase == .noVerdictForDate("No readiness verdict was computed for 2026-01-02."))
}

@Test @MainActor func anyOtherByDateFailureStaysAGenericRetryableError() async throws {
    var p = GateRationaleProvider()
    p.verdictError = HubError.unauthorized
    let vm = GateRationaleViewModel(provider: p, date: "2026-01-02")
    await vm.load()
    #expect(vm.phase == .error("Hub rejected the token — check Settings › Connection."))
}

@Test func theWeekdayLabelReadsTheHubsCalendarDayWithoutATimezoneShift() {
    #expect(GateRationaleView.weekdayLabel("2026-09-11", locale: en) == "Fri")
    #expect(GateRationaleView.weekdayLabel("not-a-date", locale: en) == "not-a-date")
}

// MARK: - r4: the board's Weekly nutrition tiles + "Last 3 days" table

@Test @MainActor func weeklyTilesReadTheGatesSevenDayAveragesNeverInvented() async throws {
    let vm = GateRationaleViewModel(provider: GateRationaleProvider())
    await vm.load()
    // planning_gate.json: avg_kcal_deficit_7d 249.3 -> balance −249.3 (the sign people read).
    #expect(vm.energyBalance7d == -249.3)
    #expect(vm.protein7d == vm.gate?.averages.avgProtein7d)

    let empty = GateRationaleViewModel(provider: GateRationaleProvider())
    #expect(empty.energyBalance7d == nil)
    #expect(empty.protein7d == nil)
}

@Test @MainActor func weeklyNotesKeepTheGatesRecommendationRulesAndSuggestionsReachable() async throws {
    var p = GateRationaleProvider()
    p.recommendation = .reduce
    p.triggeredRules = ["avg_protein_7d 118.0 vs threshold 130.0 (REDUCE: insufficient protein)"]
    p.suggestions = ["Front-load protein earlier in the day"]
    let vm = GateRationaleViewModel(provider: p)
    await vm.load()
    // W-FIX1 BUG-27: one plain sentence (the why + the gate's own suggestion), no raw hub lines.
    #expect(vm.weeklyNotes(locale: en) == ["This week (insufficient protein): front-load protein earlier in the day."])
}

@Test func lastThreeDatesCountBackFromTheVerdictDayNewestFirst() {
    #expect(GateRationaleViewModel.lastThreeDates(anchor: "2026-09-01") == ["2026-09-01", "2026-08-31", "2026-08-30"])
    #expect(GateRationaleViewModel.lastThreeDates(anchor: "garbage").isEmpty)
    #expect(GateRationaleViewModel.lastThreeDates(anchor: nil).isEmpty)
}

@Test @MainActor func lastThreeDaysShowOnlyRowsPersistedForThatExactDate() async throws {
    // The mock serves the 2026-09-11 row for any date; morning's verdict_date is 2026-09-12.
    let vm = GateRationaleViewModel(provider: GateRationaleProvider())
    await vm.load()
    let rows = vm.lastDays(locale: en)
    #expect(rows.map(\.date) == ["2026-09-12", "2026-09-11", "2026-09-10"])
    #expect(rows.map(\.dayLabel) == ["Sat 12", "Fri 11", "Thu 10"])
    #expect(rows[0].verdictWord == nil && rows[0].session == nil)
    #expect(rows[1].verdictWord == "Modified")   // the mock row is "GO (auto-regulated)" (BUG-03)
    #expect(rows[1].session == "Day 3 Full Upper + Z2 60min")
    #expect(rows[1].tone == .amber)
    #expect(rows[1].prescription == "Lift at current weights 1-2 reps shy of failure; trim Z2 to ~25min or walk.")
    #expect(rows[2].verdictWord == nil)
}

@Test @MainActor func lastThreeDaysAreEmptyWhenNoVerdictsExist() async throws {
    var p = GateRationaleProvider()
    p.verdictError = HubError.http(status: 404, detail: nil)
    let vm = GateRationaleViewModel(provider: p)
    await vm.load()
    #expect(vm.phase == .loaded)
    #expect(vm.lastDays(locale: en).allSatisfy { $0.verdictWord == nil })
}

// MARK: - B-57 W1 r5: the recovery-score card (spec §2 L2: "— Calibrating"; the score is W3)

@Test func theRecoveryScoreCardCopyInventsNoNumber() {
    #expect(!gateRationaleRecoveryScoreCopy.isEmpty)
    #expect(gateRationaleRecoveryScoreCopy.allSatisfy { !$0.isNumber })
}
