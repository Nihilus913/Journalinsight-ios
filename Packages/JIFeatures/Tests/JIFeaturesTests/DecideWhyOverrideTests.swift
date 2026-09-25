import Testing
import Foundation
import JICore
import JIDesign
import JIPersistence
@testable import JIFeatures

/// W-B57b L2 — Decide shows the why (gate-signal arcs) and writes a verdict override; the Coach
/// step is an overlay on Day; the weekly respond card lives on the gate rationale screen.
@Suite struct DecideWhyOverrideTests {
    private func signal(_ key: String, _ value: Double?, thr: Double, dir: GateSignalDirection = .min,
                        min: Double = 0, max: Double = 100, status: GateSignalStatus) -> GateSignal {
        GateSignal(key: key, label: key, value: value, unit: "", threshold: thr, direction: dir,
                   scaleMin: min, scaleMax: max, status: status)
    }

    // MARK: arcs

    @Test func tintFollowsTheHubStatus() {
        #expect(gateSignalColorRole(.pass) == .go)
        #expect(gateSignalColorRole(.amber) == .reduced)
        #expect(gateSignalColorRole(.red) == .danger)
        #expect(gateSignalColorRole(.missing) == .nested)
    }

    @Test func valueTextNeverRendersAZeroForMissing() {
        #expect(gateSignalValueText(signal("sleep", nil, thr: 70, status: .missing)) == "—")
        #expect(gateSignalValueText(signal("hrv", 24, thr: 27, max: 80, status: .amber)) == "24")
        #expect(gateSignalValueText(signal("sleep_h", 5.83, thr: 6, max: 10, status: .amber)) == "5.8")
    }

    @Test func accessibilityLabelSaysStatusAndThreshold() {
        let s = GateSignal(key: "hrv", label: "HRV", value: 24, unit: "ms", threshold: 27, direction: .min,
                           scaleMin: 0, scaleMax: 80, status: .amber)
        #expect(gateSignalAccessibilityLabel(s) == "HRV 24 ms, amber, threshold 27")
        let m = GateSignal(key: "sleep", label: "Sleep", value: nil, unit: "", threshold: 70, direction: .min,
                           scaleMin: 0, scaleMax: 100, status: .missing)
        #expect(gateSignalAccessibilityLabel(m) == "Sleep, not synced yet, threshold 70")
    }

    // MARK: effective verdict on Decide / Day / summary line

    @Test func effectivePartsCarryTheOverrideWordAndTone() {
        let parts = verdictParts("MODIFIED (HRV low) — Easy Z2 30–40 min")
        let o = VerdictOverride(date: "2026-09-23", choice: .full, reason: "Feel good despite metrics", session: "Full Upper")
        let e = effectiveVerdictParts(parts: parts, override: o)
        #expect(e.word == "FULL" && e.session == "Full Upper" && e.tone == .go)
        #expect(effectiveVerdictParts(parts: parts, override: nil) == parts)
    }

    @Test func summaryLineShowsTheEffectiveVerdict() {
        let parts = verdictParts("MODIFIED — Easy Z2 30–40 min")
        let o = VerdictOverride(date: "2026-09-23", choice: .rest, reason: nil, session: "Rest — walks only")
        #expect(morningSummaryText(verdict: effectiveVerdictParts(parts: parts, override: o), readiness: 64)
                == "REST · Rest — walks only · readiness 64")
    }

    /// Only an override for the verdict's own date counts (a stale one from yesterday never shows).
    @Test func overrideForAnotherDateIsIgnored() {
        let o = VerdictOverride(date: "2026-09-22", choice: .rest, reason: nil, session: "Rest — walks only")
        #expect(overrideForVerdictDate(o, verdictDate: "2026-09-23") == nil)
        #expect(overrideForVerdictDate(o, verdictDate: "2026-09-22") == o)
        #expect(overrideForVerdictDate(o, verdictDate: nil) == nil)
    }

    @Test func reasonLineIsTheVerdictParenthetical() {
        #expect(verdictReasonLine(verdictParts("MODIFIED (HRV low) — Easy Z2")) == "HRV low")
        #expect(verdictReasonLine(verdictParts("GO — Full Upper")) == nil)
    }

    // MARK: Adjust = choice picker

    @Test func adjustOffersFullModifiedRest() {
        let opts = adjustChoices(parts: verdictParts("MODIFIED (HRV low) — Easy Z2 30–40 min"), sessionForToday: "Full Upper")
        #expect(opts.map(\.choice) == [.full, .modified, .rest])
        #expect(opts.map(\.session) == ["Full Upper", "Easy Z2 30–40 min", "Rest — walks only"])
        #expect(opts.first?.title == "Full session")
    }

    // MARK: Go / Adjust write the override (never the weekly gate)

    @Test @MainActor func goWritesAnAcceptOverrideAndSettles() async throws {
        let db = try AppDatabase.inMemory()
        let m = VerdictOverrideViewModel(provider: MockDataProvider(), outbox: Outbox(db: db))
        let ok = await decideSubmit(model: m, date: "2026-09-23", choice: .accept, reason: "",
                                    parts: verdictParts("MODIFIED — Easy Z2 30–40 min"), sessionForToday: "Full Upper")
        #expect(ok && m.settled)
        #expect(m.current?.choice == .accept)
    }

    // MARK: fixtures + registry

    @Test @MainActor func decideFixtureHasFourSignalsWithOneAmber() throws {
        let morning = try #require(TodayViewModel.fixture(morningState: .decide)?.morning)
        let signals = try #require(morning.gateSignals)
        #expect(signals.count == 4)
        #expect(signals.filter { $0.status == .amber }.count == 1)
    }

    // MARK: B-65 context arc (daytime HRV — shown, muted, never gating)

    @Test func contextArcIsMutedNeverGreenAndShowsItsValueAndNote() {
        let s = GateSignal(key: "hrv_day", label: "HRV (day)", value: 31, unit: "ms", threshold: 0, direction: .min,
                           scaleMin: 0, scaleMax: 80, status: .context, note: "weekday — dosed")
        #expect(gateSignalColorRole(.context) == .muted)
        #expect(gateSignalColorRole(.context) != .go)
        #expect(gateSignalValueText(s) == "31")
        #expect(gateSignalNoteText(s) == "weekday — dosed")
        #expect(gateSignalAccessibilityLabel(s) == "HRV (day) 31 ms, context only, weekday — dosed")
    }

    @Test func noteIsShownOnlyForContextArcs() {
        let amber = GateSignal(key: "hrv", label: "HRV", value: 24, unit: "ms", threshold: 27, direction: .min,
                               scaleMin: 0, scaleMax: 80, status: .amber, note: "hrv 24 — under 27")
        #expect(gateSignalNoteText(amber) == nil)
    }

    @Test func contextArcDoesNotCountTowardPassOrAmberTallies() {
        let signals = [
            signal("hrv", 40, thr: 35, max: 80, status: .pass),
            signal("sleep_h", 6.5, thr: 7, max: 10, status: .amber),
            signal("hrv_day", 31, thr: 0, max: 80, status: .context),
        ]
        let gating = signals.filter(gateSignalIsGating)
        #expect(gating.map(\.key) == ["hrv", "sleep_h"])
        #expect(gating.filter { $0.status == .pass }.count == 1)
        #expect(gating.filter { $0.status == .amber }.count == 1)
    }

    @Test @MainActor func appleDecideFixtureHasThreeArcsWithOneContext() throws {
        let morning = try #require(TodayViewModel.fixture(morningState: .decide, morningJSON: fixtureMorningAppleJSON)?.morning)
        let signals = try #require(morning.gateSignals)
        #expect(signals.map(\.key) == ["hrv", "sleep_h", "hrv_day"])
        #expect(signals.filter { $0.status == .context }.count == 1)
        #expect(ScreenRegistry.entries.map(\.name).contains("Today decide Apple"))
    }

    @Test func registryHasTheAdjustSheet() {
        #expect(ScreenRegistry.entries.map(\.name).contains("Today adjust"))
    }
}

@Suite struct DecideWordTests {
    @Test func decideWordDropsTheParenthetical() {
        #expect(decideWord(verdictParts("MODIFIED (HRV low) — Easy Z2")) == "Modified")
        #expect(decideWord(verdictParts("GO — Full Upper")) == "Full")
        #expect(decideWord(verdictParts(nil)) == "—")
    }
}
