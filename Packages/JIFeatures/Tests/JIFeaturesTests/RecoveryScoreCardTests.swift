import Foundation
import Testing
import JICore
import JICompute
import JIDesign
@testable import JIFeatures

// B-57 W3 S1 — the recovery-score card on Decide (compact row) and GateRationale (full card).

private func s1Source(_ relative: String) throws -> String {
    let pkg = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: pkg.appending(path: relative), encoding: .utf8)
}

private func sig(_ k: String) -> GateSignal {
    GateSignal(key: k, label: k, value: 1, unit: "", threshold: 1, direction: .min, status: .pass)
}

private func result(_ status: RecoveryScoreStatus, score: Int?, nights: Int = 20) -> RecoveryScoreResult {
    RecoveryScoreResult(status: status, score: score, raw: score.map(Double.init), components: [], nights: nights, nightsNeeded: 14)
}

@Test func recoverySignalIsNotRenderedTwice() {
    let out = RecoveryScoreCard.visibleSignals([sig("hrv"), sig("sleep_h"), sig("recovery"), sig("hrv_day")])
    #expect(out.map(\.key) == ["hrv", "sleep_h", "hrv_day"])
}

@Test @MainActor func cardRendersWithoutAService() {
    // nil environment = inert: "— No data", no crash, no fetch.
    _ = RecoveryScoreCard().body
    _ = RecoveryScoreCard(compact: true).body
}

@Test func headlineIsTheScoreOnlyWhenThereIsOne() {
    let ok = recoveryScoreCardText(result: result(.ok, score: 62), reasonWord: nil)
    #expect(ok.numeral == "62")
    #expect(ok.caption == "In your normal range")
    #expect(ok.role == .go)
    let low = recoveryScoreCardText(result: result(.ok, score: 31), reasonWord: nil)
    #expect(low.numeral == "31")
    #expect(low.caption == "Recovery low")
    #expect(low.role == .reduced)
}

@Test func missingOrCalibratingIsADashAndAWordNeverZeroOrFifty() {
    let none = recoveryScoreCardText(result: nil, reasonWord: "No data")
    #expect(none.numeral == "—")
    #expect(none.caption == "No data")
    #expect(none.role == .muted)
    let cal = recoveryScoreCardText(result: result(.calibrating, score: nil, nights: 3), reasonWord: nil)
    #expect(cal.numeral == "—")
    #expect(cal.caption == "Calibrating · 3 of 14 nights")
    let missing = recoveryScoreCardText(result: result(.missing, score: nil), reasonWord: nil)
    #expect(missing.numeral == "—")
    #expect(missing.caption == "No data")
    // An inert card (no service at all) reads "No data".
    #expect(recoveryScoreCardText(result: nil, reasonWord: nil).caption == "No data")
}

@Test func calibratingCountNeverExceedsTheNeed() {
    let cal = recoveryScoreCardText(result: result(.calibrating, score: nil, nights: 40), reasonWord: nil)
    #expect(cal.caption == "Calibrating · 14 of 14 nights")
}

@Test func decideAndRationaleMountTheCardAndDropTheDoubledRow() throws {
    let decide = try s1Source("Sources/JIFeatures/Today/DecideView.swift")
    #expect(decide.contains("RecoveryScoreCard(compact: true"))   // W-FIX7 fixer: + hubRecovery
    #expect(decide.contains("RecoveryScoreCard.visibleSignals("))
    let rationale = try s1Source("Sources/JIFeatures/GateRationale/GateRationaleView.swift")
    #expect(rationale.contains("RecoveryScoreCard(gateRows: model.morning?.gateSignals)"))   // W-FIX-P2 RG-38: the call's gate rows
    #expect(rationale.contains("RecoveryScoreCard.visibleSignals("))
    // The W-GUI placeholder ("— Calibrating · n of 7 nights") is gone: 14 nights is the real need.
    #expect(!rationale.contains("of 7 nights"))
}
