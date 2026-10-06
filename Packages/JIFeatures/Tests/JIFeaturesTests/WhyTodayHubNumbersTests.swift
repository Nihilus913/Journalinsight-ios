import Testing
import JICore
import JICompute
import JIDesign
@testable import JIFeatures

/// RG-38 (W-FIX-P2, B-105): the Why-today card says the same numbers as Decide's "What drove it"
/// (the hub's gate rows): Recovery 39 (not the phone's 44), Load "Overreaching" (not "In your
/// normal"), and the "One change today" comparisons read against the gate rows' own normal band.
@Suite struct WhyTodayHubNumbersTests {
    /// The 2026-10-05 gate rows (Decide "What drove it").
    static let gateRows: [GateSignal] = {
        var load = GateSignal(key: "load", label: "Load", value: 1.84, unit: "", threshold: 1.5, direction: .max, status: .red)
        load.loadStatus = "overreaching"
        return [
            GateSignal(key: "recovery", label: "Recovery score", value: 39, unit: "", threshold: 50, direction: .min, status: .amber),
            GateSignal(key: "hrv", label: "HRV", value: 21, unit: "ms", threshold: 27, direction: .min, status: .amber,
                       bandLo: 27, bandHi: 41),
            GateSignal(key: "sleep", label: "Sleep", value: 72, unit: "", threshold: 70, direction: .min, status: .pass,
                       bandLo: 70, bandHi: 90),
            GateSignal(key: "rhr", label: "RHR", value: 58, unit: "bpm", threshold: 65, direction: .max, status: .pass,
                       bandLo: 50, bandHi: 60),
            load,
        ]
    }()

    @Test func headlineIsTheGateRecoveryRow() {
        let text = recoveryScoreCardText(result: nil, reasonWord: nil, hubRecovery: decideHubRecovery(Self.gateRows),
                                         hubStatus: decideHubRecoveryStatus(Self.gateRows))
        #expect(text.numeral == "39")
        #expect(text.caption == "Recovery low")
    }

    @Test func driverWordsFollowTheGateRows() {
        let phone = RecoveryCardModel.make(result: nil, reasonWord: nil, sleepGoalH: nil)
        let model = phone.applyingGateRows(Self.gateRows)
        let words = Dictionary(uniqueKeysWithValues: model.drivers.map { ($0.id, $0.word) })
        #expect(words["load"] == "Overreaching")
        #expect(words["hrv"] == "Low")
        #expect(words["sleep"] == "In your normal")
        #expect(words["rhr"] == "In your normal")
        #expect(model.headline == "39")
        #expect(model.isLow)
    }

    @Test func noGateRowsKeepsThePhoneCard() {
        let phone = RecoveryCardModel.make(result: nil, reasonWord: nil, sleepGoalH: nil)
        #expect(phone.applyingGateRows(nil) == phone)
        #expect(phone.applyingGateRows([]) == phone)
    }

    @Test func coachSignalsReadAgainstTheGateRowBands() {
        let content = CoachContentBuilder.build(morning: nil, gate: nil, recovery: [], gateSignals: Self.gateRows)
        #expect(content.signals == ["Sleep 72 (normal 70–90)", "HRV 21 ms (normal 27–41)", "RHR 58 bpm (normal 50–60)"])
    }

    @Test func coachSignalsFallBackToGateValueWithoutBand() {
        let rows = [GateSignal(key: "hrv", label: "HRV", value: 30, unit: "ms", threshold: 27, direction: .min, status: .pass)]
        let content = CoachContentBuilder.build(morning: nil, gate: nil, recovery: [], gateSignals: rows)
        #expect(content.signals == ["HRV 30 ms (threshold 27)"])
    }
}
