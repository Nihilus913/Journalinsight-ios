import Foundation
import Testing
import JICore
@testable import JIFeatures

/// RG-37 (B-104): "HRV (7-day)" on What drove it (22 ms, the gate's rolling value) and the HRV
/// detail's 7-day row (was 23 ms, a different mean) use one definition — same value, same label.
@Suite struct HrvSevenDayOneDefinitionTests {
    let gate = GateSignal(key: "hrv", label: "HRV (7-day)", value: 22, unit: "ms", threshold: 23,
                          direction: .min, status: .amber, note: "HRV 7-day 22 ms — under band 23–27 ms")

    /// Seven nights whose arithmetic mean is 23 ms (the detail's old number).
    let history: [(date: String, value: Double?)] = [17, 19, 21, 23, 25, 27, 29].enumerated().map { i, v in
        (date: "2026-10-0\(i + 1)", value: v)
    }

    @Test func detailRowAndGateRowShowTheSameValueAndLabel() throws {
        let rows = kpiDetailTableRows(history: history, value: 29, unit: "ms", decimals: 0, hubSevenDay: gate.value)
        let avg7 = try #require(rows.first { $0.id == "avg7" })
        let decide = decideSignalRowModel(gate)
        #expect(avg7.value == "22 ms")
        #expect(decide.value == 22)
        #expect(decide.label.hasSuffix(avg7.title))
        #expect(avg7.title == kpiHrvSevenDayLabel)
        #expect(kpiHrvSevenDayLabel.contains("incl. last night"))
    }

    @Test func withoutTheHubValueTheRowKeepsItsOwnMean() throws {
        let rows = kpiDetailTableRows(history: history, value: 29, unit: "ms", decimals: 0)
        let avg7 = try #require(rows.first { $0.id == "avg7" })
        #expect(avg7.title == "7-day average")
        #expect(avg7.value == "23 ms")
    }
}
