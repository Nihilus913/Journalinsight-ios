import Foundation
import Testing
import JICore
@testable import JIFeatures

/// W-FIX1 lane L4 — verdict truth. One failing-first test per BUG row
/// (`HealthTraining/docs/audits/2026-09-25-regression-bugs.md`).
private let en = Locale(identifier: "en_US")

/// The hub's 2026-09-25 amber day (`/tmp/w-reg1/r1/morning-verdict.json`).
private let amberVerdict = "GO (auto-regulated) — Day 3 Full Upper + Z2 60min"
private let amberReason = "Amber (overnight vitals not synced yet): lift at current weights 1-2 reps shy of failure; trim Z2 to ~25min or walk."

private func morning(_ verdict: String?, date: String = "2026-09-25") -> MorningResponse {
    let v = verdict.map { "\"\($0)\"" } ?? "null"
    let json = #"{"today_activities":[],"verdict":\#(v),"verdict_date":"\#(date)","carb_watch_floor":120,"hrv_series":[]}"#
    return try! JSON.decoder.decode(MorningResponse.self, from: Data(json.utf8))
}

private func gate(_ recommendation: String, rules: [String] = [], suggestions: [String] = [], deficit: Double? = nil) -> GateResponse {
    let r = rules.map { "\"\($0)\"" }.joined(separator: ",")
    let s = suggestions.map { "\"\($0)\"" }.joined(separator: ",")
    let d = deficit.map { "\($0)" } ?? "null"
    let json = #"""
    {"recommendation":"\#(recommendation)","window_days":28,"tracked_days":6,"total_days":7,"min_tracked_days":4,
     "triggered_rules":[\#(r)],"suggestions":[\#(s)],"daily":[],
     "averages":{"avg_kcal_deficit_7d":\#(d),"trends":{}}}
    """#
    return try! JSON.decoder.decode(GateResponse.self, from: Data(json.utf8))
}

// MARK: - BUG-03: amber auto-regulation shows Modified with the reduced prescription

@Test func bug03_autoRegulatedGoIsModifiedNotFull() {
    #expect(verdictUserWord(verdictParts(amberVerdict)) == VerdictUserWord.modified)
    #expect(decideWord(verdictParts(amberVerdict)) == "Modified")
    // A plain GO stays Full.
    #expect(verdictUserWord(verdictParts("GO — Day 3 Full Upper + Z2 60min")) == "Full")
}

@Test func bug03_autoRegulatedGoIsTintedAmberEverywhere() {
    let p = verdictParts(amberVerdict)
    #expect(effectiveVerdictParts(parts: p, override: nil).tone == .amber)
    #expect(effectiveVerdictTone(parts: p, override: nil) == .amber)
    #expect(effectiveVerdictParts(parts: verdictParts("GO — x"), override: nil).tone == .go)
}

@Test func bug03_theReducedPrescriptionComesFromTheHubReasonFirst() {
    let p = verdictParts(amberVerdict)
    #expect(autoRegulatedPrescription(p, reason: amberReason) == "Lift at current weights 1-2 reps shy of failure; trim Z2 to ~25min or walk.")
    #expect(autoRegulatedWhy(p, reason: amberReason) == "overnight vitals not synced yet")
}

@Test func bug03_withoutAReasonThePrescriptionIsTheHubsFixedAmberCopyForTheSessionType() {
    #expect(autoRegulatedPrescription(verdictParts(amberVerdict)) == AutoRegulatedCopy.strength)
    #expect(autoRegulatedPrescription(verdictParts("GO (auto-regulated) — Long Zone 2 75-90min")) == AutoRegulatedCopy.longZ2)
    // Unknown session: never guessed.
    #expect(autoRegulatedPrescription(verdictParts("GO (auto-regulated) — Mystery session")) == nil)
    // Not auto-regulated: no prescription.
    #expect(autoRegulatedPrescription(verdictParts("GO — Day 3 Full Upper + Z2 60min"), reason: amberReason) == nil)
}

@Test func bug03_decideShowsThePrescriptionLineUntilTheUserMakesAnotherCall() {
    let p = verdictParts(amberVerdict)
    #expect(decidePrescriptionLine(verdict: p, override: nil) == AutoRegulatedCopy.strength)
    let accept = VerdictOverride(date: "2026-09-25", choice: .accept, reason: nil, session: "")
    #expect(decidePrescriptionLine(verdict: p, override: accept) == AutoRegulatedCopy.strength)
    let full = VerdictOverride(date: "2026-09-25", choice: .full, reason: nil, session: "")
    #expect(decidePrescriptionLine(verdict: p, override: full) == nil)
    // "(auto-regulated)" is not a reason line.
    #expect(verdictReasonLine(p) == nil)
}

@Test func bug03_theDayInsightCarriesTheTrimmedPrescription() {
    let s = InsightSentence.build(gate: gate("MAINTAIN"), morning: morning(amberVerdict))
    #expect(s.contains("Day 3 Full Upper + Z2 60min"))
    #expect(s.contains("trim Z2 to ~25min or walk"))
    #expect(!s.contains("GO"))
}

@Test @MainActor func bug03_gateRationaleShowsModifiedWithThePrescriptionAndWhy() async throws {
    let vm = GateRationaleViewModel(provider: MockDataProvider(), date: "2026-09-11")
    await vm.load()
    #expect(vm.verdictWord == "Modified")
    #expect(vm.verdict.tone == .amber)
    #expect(vm.verdictPrescription == "Lift at current weights 1-2 reps shy of failure; trim Z2 to ~25min or walk.")
    #expect(vm.verdictWhy == "HRV 23, RHR 66")
}

// MARK: - BUG-07 (app): Energy balance = intake − expenditure, 7-day avg (B-73), as the hub serves it

@Test func bug07_theBalanceIsIntakeMinusExpenditureNeverTheGoalGap() {
    // Hub (L1): avg_kcal_deficit_7d = expenditure − intake over 7 days → balance is its negation.
    #expect(weeklyEnergyBalance(gate("MAINTAIN", deficit: 598.1).averages) == -598.1)
    #expect(weeklyEnergyBalance(gate("MAINTAIN", deficit: -120).averages) == 120)
    // Missing stays missing ("—" + No data), never zero.
    #expect(weeklyEnergyBalance(gate("MAINTAIN").averages) == nil)
    // The explainer on the same path says the same definition.
    #expect(JIExplainers.energyBalanceSteps.map(\.title).contains("Balance = eaten − burned, 7-day average"))
}

// MARK: - BUG-17: Decide "Today's session" row links to Day

@Test func bug17_theSessionRowOpensDayOnceTheVerdictIsIn() {
    #expect(decideSessionRowOpensDay(syncing: false))
    #expect(!decideSessionRowOpensDay(syncing: true))
}

// MARK: - BUG-18: the whole Adjust reason row selects the reason

/// Source-level guard (no view-inspection harness in the host suites): the reason row's padding,
/// full width and background must sit INSIDE the Button's label with a rectangular content shape —
/// the defect was `Button(r) {…}.padding(…).frame(maxWidth: .infinity).background(…)`, which leaves
/// only the text hit-testable.
@Test func bug18_theReasonRowsHitAreaIsTheWholeRow() throws {
    let src = try String(contentsOf: decideViewSource(), encoding: .utf8)
    let start = try #require(src.range(of: "private func reasonRow(_ r: String)"))
    let body = String(src[start.upperBound...].prefix(1400))
    #expect(!body.contains("Button(r)"))
    let label = try #require(body.range(of: "} label: {"))
    let style = try #require(body.range(of: ".buttonStyle("))
    let inside = String(body[label.upperBound..<style.lowerBound])
    #expect(inside.contains(".frame(maxWidth: .infinity"))
    #expect(inside.contains(".background("))
    #expect(inside.contains(".contentShape(Rectangle())"))
}

private func decideViewSource() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/JIFeatures/Today/DecideView.swift")
}

// MARK: - BUG-27: user words (Full / Modified / Rest) and one plain sentence, everywhere

@Test func bug27_theDaySummaryLineLeadsWithTheUserWord() {
    #expect(morningSummaryText(verdict: verdictParts(amberVerdict), readiness: 78) == "Modified · Day 3 Full Upper + Z2 60min · readiness 78")
    #expect(morningSummaryText(verdict: verdictParts("GO — Full Upper"), readiness: nil) == "Full · Full Upper")
}

@Test func bug27_theHeroLeadIsTheUserWordAndTheWeeklyGateIsItsOwnSentence() {
    let s = InsightSentence.build(
        gate: gate("REDUCE", rules: ["avg_kcal_7d 1456.4 vs threshold 1600.0 (REDUCE: under-fueling)"]),
        morning: morning("GO — Day 3 Full Upper + Z2 60min"))
    #expect(!s.contains("REDUCE") && !s.contains("GO"))
    #expect(s.hasPrefix("Day 3 Full Upper + Z2 60min. This week (under-fueling): "))
    let line = insightLine(word: verdictUserWord(verdictParts("GO — x")), sentence: s)
    #expect(line.lead == "Full")
}

@Test func bug27_noRawHubWordInAnyInsightBranch() {
    let raw = ["GO", "REDUCE", "REDUCED", "MODIFIED", "PROGRESS", "MAINTAIN"]
    let sentences = [
        InsightSentence.build(gate: gate("MAINTAIN"), morning: morning("REDUCED — deload dose, not a day off")),
        InsightSentence.build(gate: gate("MAINTAIN"), morning: morning("MODIFIED — swap intervals for easy Z2 30-40min")),
        InsightSentence.build(gate: gate("PROGRESS", suggestions: ["Try increasing bench press by 2.5 kg"]), morning: morning("GO — Day 1")),
        InsightSentence.build(gate: gate("MAINTAIN"), morning: morning("GO — Day 1")),
    ]
    for s in sentences {
        for w in raw { #expect(!s.split(whereSeparator: { !$0.isLetter }).contains(Substring(w)), "\(w) in \(s)") }
    }
}

@Test func bug27_trainingGateDetailCardSpeaksPlainly() {
    #expect(gateDetailWeeklyLine(gate("REDUCE")) == "This week's nutrition says ease off — fuel and recovery are short.")
    #expect(gateDetailWeeklyLine(nil) == nil)
    for rec in ["PROGRESS", "MAINTAIN", "REDUCE", "INSUFFICIENT_DATA"] {
        let line = gateDetailWeeklyLine(gate(rec)) ?? ""
        #expect(!line.contains(rec) && !line.contains("Gate recommendation"))
    }
}

@Test @MainActor func bug27_gateRationaleWeeklyNoteIsOnePlainSentence() async throws {
    var p = FixL4GateProvider()
    p.rules = ["avg_kcal_7d 1456.4 vs threshold 1600.0 (REDUCE: under-fueling)"]
    let vm = GateRationaleViewModel(provider: p)
    await vm.load()
    let notes = vm.weeklyNotes(locale: en)
    #expect(notes == ["This week (under-fueling): bring kcal back up toward goal — this is chronic under-fueling, not a plateau."])
}

@Test func bug27_gateConfigPreviewShowsTheUserWord() throws {
    let result = try previewMorningGateVerdict(MorningGateOverrides())
    #expect(result.verdict == "GO — Norwegian 4x4 intervals")     // raw stays for the flip compare
    #expect(result.displayVerdict == "Full · Norwegian 4x4 intervals")
    #expect(GatePreviewResult(verdict: "MODIFIED — swap intervals for easy Z2 30-40min", conditions: []).displayVerdict
        == "Modified · swap intervals for easy Z2 30-40min")
}

@Test func bug27_anOverrideCaptionSaysTheUserWord() {
    let full = VerdictOverride(date: "2026-09-25", choice: .full, reason: "Feel good", session: "")
    #expect(effectiveVerdict(parts: verdictParts(amberVerdict), override: full).wasCaption == "was Modified · Feel good")
    // Modified over an amber day is not a change.
    let modified = VerdictOverride(date: "2026-09-25", choice: .modified, reason: nil, session: "")
    #expect(effectiveVerdict(parts: verdictParts(amberVerdict), override: modified).wasCaption == nil)
}

private struct FixL4GateProvider: HealthDataProvider {
    let capabilities: DataCapability = .hubAll
    private let inner = MockDataProvider()
    var rules: [String] = []
    func health() async throws -> HealthResponse { try await inner.health() }
    func gate(windowDays: Int) async throws -> GateResponse {
        var g = try await inner.gate(windowDays: windowDays)
        g.recommendation = .reduce; g.triggeredRules = rules; g.suggestions = []
        return g
    }
    func morning() async throws -> MorningResponse { try await inner.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await inner.morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { try await inner.recovery(windowDays: windowDays) }
    func syncStatus() async throws -> SyncStatus { try await inner.syncStatus() }
}
