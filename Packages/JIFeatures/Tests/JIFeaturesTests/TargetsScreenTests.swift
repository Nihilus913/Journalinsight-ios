import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

// W-TGT L3 (spec HT docs/superpowers/specs/2026-09-28-targets-alignment-design.md §4, mocks 01–05):
// Settings › Targets, the editor sheet, the KPI Targets card and every screen that reads a goal.
// Test values only (not anyone's goals).

private func sample() -> TargetsDocument {
    var d = TargetsDocument()
    d.goals.weight = WeightTarget(baseKg: 82.0, targetKg: 76.5, targetDate: "2026-11-30")
    d.goals.kcal = KcalGoal(goalKcal: 2200, basis: .subtractDeficit(.deficit(kcalPerDay: 450)))
    d.goals.proteinG = 150
    d.goals.stepsDaily = 8500
    d.limits = TargetLimits(hrCapBpm: 168, hrCapConfirmedOn: "2026-09-20",
                            zones: HrZones(anchor: .lthr, anchorBpm: 170, floorsBpm: [110, 128, 145, 160, 171]), avoidZone5: true)
    d.rules[.weekProteinFloor] = 125
    return d
}

// MARK: - Rows (mock 01)

@Test func goalRowsShowTheUsersNumbersAndNoGoalWithoutOne() {
    let rows = TargetsRows.goals(sample())
    #expect(rows.map(\.title) == ["Weight", "Calories", "Protein", "Carbs", "Fat", "Daily steps", "Sleep"])
    let byTitle = Dictionary(uniqueKeysWithValues: rows.map { ($0.title, $0) })
    #expect(byTitle["Weight"]?.value == "76.5 kg")
    #expect(byTitle["Weight"]?.subtitle == "by 30 Nov 2026")
    #expect(byTitle["Calories"]?.value == "1,750 kcal")
    #expect(byTitle["Calories"]?.subtitle == "goal 2,200 − deficit 450")
    #expect(byTitle["Protein"]?.value == "150 g")
    #expect(byTitle["Carbs"]?.value == "— g")
    #expect(byTitle["Carbs"]?.subtitle == "no goal")
    #expect(byTitle["Daily steps"]?.value == "8,500 steps")
    // D2: the sleep goal is never seeded.
    #expect(byTitle["Sleep"]?.value == "— h")
    #expect(rows.allSatisfy { $0.ruleTag == nil })
}

@Test func anEmptyDocumentHasNoNumbersAnywhere() {
    for row in TargetsRows.goals(.empty) { #expect(row.value.hasPrefix("—"), "\(row.title) shows \(row.value)") }
    let limits = TargetsRows.limits(.empty, today: "2026-09-28")
    #expect(limits.map(\.value) == ["No cap", "—", "Off"])
    #expect(targetsSettingsSummary(.empty) == "no goals · no cap · rules recommended")
}

@Test func limitRowsNameTheCapItsConfirmationAndTheZones() {
    let rows = TargetsRows.limits(sample(), today: "2026-09-28")
    #expect(rows[0].value == "168 bpm")
    #expect(rows[0].subtitle == "confirmed 20 Sep · re-check every 8 wk")
    #expect(rows[1].subtitle == "from LTHR 170 · Z5 from 171")
    #expect(rows[1].value == "5 floors")
    #expect(rows[2].value == "On")
}

@Test func ruleRowsSayRecommendedUntilChangedAndYoursAfter() {
    let rows = TargetsRows.rules(sample())
    let byTitle = Dictionary(uniqueKeysWithValues: rows.map { ($0.title, $0) })
    #expect(byTitle["How cautious"]?.value == "2 nights")
    #expect(byTitle["How cautious"]?.subtitle == "Balanced · modified after 2 low HRV nights in a row")
    #expect(byTitle["Breathing rate"]?.value == "+2.0 /min")
    #expect(byTitle["Load band"]?.value == "0.80–1.30")
    #expect(byTitle["Week under fuel"]?.value == "1,600 kcal")
    #expect(byTitle["Week under fuel"]?.ruleTag == "recommended")
    #expect(byTitle["Week under protein"]?.value == "125 g")
    #expect(byTitle["Week under protein"]?.ruleTag == "yours")
    #expect(byTitle["Week of poor sleep"]?.value == "55")
}

@Test func settingsRowSummaryCountsGoalsCapAndRules() {
    #expect(targetsSettingsSummary(sample()) == "4 goals · cap 168 · 1 rule yours")
}

@Test func copyNeverSaysThresholdOrOverride() {
    var words = [TargetsRows.subtitle, TargetsRows.rulesIntro, TargetsRows.limitsFooter, TargetsRows.strengthFooter,
                 TargetsRows.resetFooter, kpiTargetsCardCaption, gateConfigFooter]
    for r in RuleMetric.allCases { words += [targetsRuleTitle(r), targetsRuleExplanation(r)] }
    for w in words {
        #expect(!w.lowercased().contains("threshold"), "\(w)")
        #expect(!w.lowercased().contains("override"), "\(w)")
    }
}

// MARK: - Parsing + the editor draft (mock 02)

@Test func typedNumbersParseWithoutGuessing() {
    #expect(targetsParse("") == .none)
    #expect(targetsParse("  ") == .none)
    #expect(targetsParse("1,617") == .value(1617))
    #expect(targetsParse("7,5") == .value(7.5))
    #expect(targetsParse("7.25") == .value(7.25))
    #expect(targetsParse("12,000") == .value(12000))
    #expect(targetsParse("abc") == .invalid)
}

@Test func theKcalDraftSubtractsTheDeficitOnceAndSaysTheTarget() throws {
    var d = TargetEditDraft(subject: .goal(.kcal), document: .empty)
    #expect(d.goalText.isEmpty && d.deficitText.isEmpty)
    d.goalText = "2117"; d.deficitText = "500"
    #expect(d.kcalTargetPreview == 1617)
    let doc = try d.applied(to: .empty).get()
    #expect(doc.goal(.kcal) == 1617)
    #expect(doc.goals.kcal?.basis == .subtractDeficit(.deficit(kcalPerDay: 500)))
    d.trackerIncludesDeficit = true
    #expect(d.kcalTargetPreview == 2117)          // JI never subtracts twice
    #expect(try d.applied(to: .empty).get().goals.kcal?.basis == .includesDeficit)
}

@Test func theKcalDraftRoundTripsTheStoredBasis() {
    let loss = TargetsDocument(goals: TargetGoals(kcal: KcalGoal(goalKcal: 2300, basis: .subtractDeficit(.weeklyLoss(kgPerWeek: 0.5)))))
    let d = TargetEditDraft(subject: .goal(.kcal), document: loss)
    #expect(d.deficitIsWeeklyLoss && d.deficitText == "0.50")
    #expect((try? d.applied(to: loss).get()) == loss)          // saving unchanged changes nothing
    let sample = sample()
    #expect((try? TargetEditDraft(subject: .goal(.kcal), document: sample).applied(to: sample).get()) == sample)
}

@Test func aBlankGoalIsNoGoalAndABlankRuleIsRecommended() throws {
    var d = TargetEditDraft(subject: .goal(.protein), document: sample())
    #expect(d.goalText == "150")
    #expect(d.ruleTexts[.weekProteinFloor] == "125")
    d.goalText = ""; d.ruleTexts[.weekProteinFloor] = ""
    let doc = try d.applied(to: sample()).get()
    #expect(doc.goals.proteinG == nil)
    #expect(doc.rules[.weekProteinFloor] == nil)
    #expect(doc.rule(.weekProteinFloor) == RuleMetric.weekProteinFloor.recommended)
    #expect(doc.goals.kcal == sample().goals.kcal)          // nothing else moves
    #expect(doc.limits == sample().limits)
}

@Test func unreadableTextSavesNothing() {
    var d = TargetEditDraft(subject: .goal(.steps), document: sample())
    d.goalText = "lots"
    #expect(d.applied(to: sample()) == .failure(.unreadable("Daily steps")))
}

@Test func sleepStepsAndWeightDrafts() throws {
    var sleep = TargetEditDraft(subject: .goal(.sleep), document: .empty)
    sleep.goalText = "7"
    #expect(try sleep.applied(to: .empty).get().goals.sleepH == 7)
    var steps = TargetEditDraft(subject: .goal(.steps), document: .empty)
    steps.goalText = "9,000"
    #expect(try steps.applied(to: .empty).get().goals.stepsDaily == 9000)
    var weight = TargetEditDraft(subject: .goal(.weight), document: sample())
    #expect(weight.goalText == "76.5" && weight.weightDate == "2026-11-30")
    weight.goalText = "75"; weight.weightDate = nil
    let w = try weight.applied(to: sample()).get().goals.weight
    #expect(w == WeightTarget(baseKg: 82.0, targetKg: 75, targetDate: nil))   // the start weight is kept
    weight.goalText = ""
    #expect(try weight.applied(to: sample()).get().goals.weight == nil)
}

@Test func theLoadBandEditsItsFourRulesTogether() throws {
    var d = TargetEditDraft(subject: .loadBand, document: .empty)
    #expect(d.ruleTexts[.loadBandLow] == "0.80" && d.ruleTexts[.loadOver] == "1.30")
    d.ruleTexts[.loadBandHigh] = "1.25"
    let doc = try d.applied(to: .empty).get()
    #expect(doc.rule(.loadBandHigh) == 1.25)
    #expect(!doc.isRecommended(.loadBandHigh))
    #expect(doc.isRecommended(.loadBandLow))
}

@Test func steppingStartsFromTheTypedValueOrTheRecommendation() {
    #expect(TargetEditDraft.stepped("1600", by: 50, decimals: 0, from: nil) == "1,650")   // grouped like its caption
    #expect(TargetEditDraft.stepped("", by: -0.05, decimals: 2, from: 1.30) == "1.25")
    #expect(TargetEditDraft.stepped("", by: 50, decimals: 0, from: nil) == "")   // a goal never starts from a default
}

// MARK: - KPI detail Targets card (mock 03)

@Test func kpiTargetsCardShowsGoalRuleAndSaysRecommended() {
    let lines = kpiTargetsCardLines(metric: .kcal, document: sample())
    #expect(lines?.goal == "1,750 kcal · deficit 450 included")
    #expect(lines?.rule == "week under 1,600 kcal → Reduce")
    #expect(lines?.ruleRecommended == true)
    #expect(kpiTargetsCardLines(metric: .protein, document: sample())?.ruleRecommended == false)
    #expect(kpiTargetsCardLines(metric: .sleep, document: .empty)?.goal == "no goal")
    #expect(kpiTargetsCardLines(metric: .hrv, document: sample()) == nil)      // nothing clinical
    #expect(kpiTargetsCardLines(metric: .acwr, document: .empty)?.goal == nil)
}

// MARK: - The model: one document, one mirror

@Test @MainActor func editingATargetSavesLocallyQueuesOneBodyAndTellsTheShell() async throws {
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    try TargetsStore(prefs: prefs).save(.empty)
    let outbox = Outbox(db: db)
    let hub = TargetsHubFake()
    var changes: [TargetsDocument] = []
    let model = TargetsModel(prefs: prefs, mirror: TargetsMirror(prefs: prefs, outbox: outbox, drainer: OutboxDrainer(outbox: outbox, hub: hub)), onChange: { changes.append($0) })
    await model.update { $0.goals.kcal = KcalGoal(goalKcal: 1700, basis: .includesDeficit) }
    #expect(model.document.goal(.kcal) == 1700)
    #expect(TargetsStore(prefs: prefs).load().goal(.kcal) == 1700)
    #expect(hub.puts.last?.goal(.kcal) == 1700)
    #expect(!model.hubPending)
    #expect(changes.last?.goal(.kcal) == 1700)
}

@Test @MainActor func anOfflineEditStaysQueuedAndSaysSo() async throws {
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    try TargetsStore(prefs: prefs).save(.empty)
    let outbox = Outbox(db: db)
    let hub = TargetsHubFake(); hub.fail = .network("down")
    let model = TargetsModel(prefs: prefs, mirror: TargetsMirror(prefs: prefs, outbox: outbox, drainer: OutboxDrainer(outbox: outbox, hub: hub)))
    await model.update { $0.goals.sleepH = 7 }
    #expect(model.hubPending)
    #expect(TargetsStore(prefs: prefs).load().goals.sleepH == 7)
    #expect(try outbox.pending().map(\.kind) == [TargetsDocument.outboxKind])
}

@Test @MainActor func resetRulesNeverTouchesGoalsOrLimits() async throws {
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    var doc = sample(); doc.rules[.hrvLowNights] = 1
    try TargetsStore(prefs: prefs).save(doc)
    let model = TargetsModel(prefs: prefs)
    await model.resetRules()
    #expect(RuleMetric.allCases.allSatisfy(model.document.isRecommended))
    #expect(model.document.goals == sample().goals)
    #expect(model.document.limits == sample().limits)
}

/// Card exit: edit kcal in Targets → Today Fuel, KPI captions / detail (the nutrition snapshot every
/// one of them reads) and Goals all read the new number.
@Test @MainActor func editingKcalInTargetsReachesFuelKpiAndGoals() async throws {
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    try TargetsStore(prefs: prefs).save(.empty)
    let model = TargetsModel(prefs: prefs)
    var d = TargetEditDraft(subject: .goal(.kcal), document: model.document)
    d.goalText = "1900"; d.trackerIncludesDeficit = true
    await model.save(try d.applied(to: model.document).get())
    // The band / Fuel / KPI source (`MacroGoalsStore` → `NutritionGoalsSnapshot`).
    #expect(try MacroGoalsStore(prefs: prefs).load().targetKcal == 1900)
    #expect(NutritionGoalsSnapshot(targets: model.document).kcalGoal == 1900)
    #expect(dayFuel(daily: [], today: "2026-09-28", kcalGoal: NutritionGoalsSnapshot(targets: model.document).kcalGoal).kcalGoal == 1900)
    // KPI detail's card.
    #expect(kpiTargetsCardLines(metric: .kcal, document: model.document)?.goal == "1,900 kcal")
    // Goals overview.
    let goals = goalsFromTargets(model.storedDocument, hub: nil)
    #expect(goals?.nutrition.kcalGoal == 1900)
    #expect(GoalsBoard.targets(goals: goals, macros: model.document.macroGoals, yesterdayKcal: nil, yesterdayProteinG: nil,
                               yesterdaySteps: nil).first?.subtitle == "goal 1,900 a day")
}

/// §5 at launch over the app's OfflineCache: a rule the user changed on the hub (`kpi.targets`) is
/// carried over, never reset to the recommendation; the sleep goal stays nil.
@Test @MainActor func launchImportReadsTheAppCacheAndSeedsNothing() throws {
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    try cache.put(TargetsStore.kpiTargetsCacheKey, [KpiTarget(targetId: 4, metric: "avg_kcal_7d", operator: "<", threshold: 1550)])
    try MacroGoalsStore(prefs: prefs).save(MacroGoals(proteinG: 140))
    TargetsModel.migrateAtLaunch(prefs: prefs, cache: cache, goals: nil, outbox: Outbox(db: db))
    let doc = TargetsStore(prefs: prefs).load()
    #expect(doc.rule(.weekKcalFloor) == 1550)
    #expect(doc.goals.proteinG == 140)
    #expect(doc.goals.sleepH == nil)
    #expect(doc.limits.hrCapBpm == nil)
    #expect(TargetsModel(prefs: prefs).isStored)
}

// MARK: - Readers

@Test func decideSleepRowSaysGoalOnlyOnceTyped() {
    let s = GateSignal(key: "sleep_h", label: "Sleep time", value: 7.4, unit: "h", threshold: 7, direction: .min,
                       status: .pass, note: nil)
    let none = decideSignalRowModel(s)
    #expect(none.detail == nil)                                  // D2: no goal word
    let typed = decideSignalRowModel(s, sleepGoalH: 7.5)
    #expect(typed.detail == "goal 7.5 h")
    #expect(typed.status == .belowGoal)
    #expect(decideSignalRowModel(s, sleepGoalH: 7).detail == "goal 7 h")
    #expect(decideSignalRowModel(s, sleepGoalH: 7).status == .aboveGoal)
}

@Test func recoverySleepDriverUsesTheGoalOnlyWhenThereIsOne() {
    let comp = RecoveryComponent(key: .sleep, status: .ok, value: 6.5, z: 0.2, normalN: 20)
    let result = RecoveryScoreResult(status: .ok, score: 70, raw: 0.1, components: [comp], nights: 20)
    let withGoal = RecoveryCardModel.make(result: result, reasonWord: nil, sleepGoalH: 7)
    #expect(withGoal.drivers.first { $0.id == "sleep" }?.word == "Below goal")
    let none = RecoveryCardModel.make(result: result, reasonWord: nil, sleepGoalH: nil)
    #expect(none.drivers.first { $0.id == "sleep" }?.word == "In your normal")
}

@Test func kpiSquaresReadTheirGoalFromTargets() {
    #expect(kpiListGoalCaption(.steps, value: 6420, targets: sample()) == "goal 8,500")
    #expect(kpiListGoalCaption(.weight, value: 79.5, targets: sample()) == "goal 76.5")
    #expect(kpiListGoalCaption(.sleep, value: 80, targets: .empty) == nil)   // fixer 2 R2: score square, hours goal
    #expect(kpiListGoalCaption(.acwr, value: 1.04, targets: .empty) == "band 0.80–1.30")
    #expect(kpiListGoalCaption(.kcal, value: 1540, targets: sample()) == "goal 1,750")   // fixer 1f: Targets, not a band word
    #expect(kpiListGoalCaption(.kcal, value: 1540, targets: nil) == nil)           // no document: the nutrition snapshot decides
}

@Test func goalsRowsOpenTheirOwnGoal() {
    #expect(goalsRowSubject("Calories") == .goal(.kcal))
    #expect(goalsRowSubject("Daily steps") == .goal(.steps))
    #expect(goalsRowSubject(goalsTrainingPlanTitle) == nil)
    #expect(goalsFromTargets(nil, hub: nil) == nil)
    #expect(goalsFromTargets(.empty, hub: nil)?.weight.targetKg.isFinite == false)   // no weight goal = no hero
}

@Test func onTodayRowCountsTheSquares() {
    #expect(onTodayTrailing(chosen: 6, total: 12) == "6 of 12")
    #expect(onTodayTrailing(chosen: 0) == "None chosen")
}
