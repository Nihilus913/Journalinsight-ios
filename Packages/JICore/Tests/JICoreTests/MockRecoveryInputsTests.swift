import Foundation
import Testing
@testable import JICore

/// B-57 W3 D1 — the mock gives the Gallery and the sweep a real (non-calibrating) history.
@Test func mockRecoveryInputsAre42AscendingDaysEndingAtDate() async throws {
    let days = try await MockDataProvider().recoveryInputs(date: "2026-09-24", windowDays: 42)
    #expect(days.count == 42)
    #expect(days.first?.date == "2026-08-14" && days.last?.date == "2026-09-24")
    #expect(days.map(\.date) == days.map(\.date).sorted())
    #expect(days.allSatisfy { $0.hrvMs != nil && $0.sleepH != nil })
}

@Test func mockRecoveryInputsBadDateIsEmptyNotInvented() async throws {
    let days = try await MockDataProvider().recoveryInputs(date: "not-a-date", windowDays: 42)
    #expect(days.isEmpty)
}

@Test func recoveryInputDayDecodesSnakeCaseAndNulls() throws {
    let json = #"{"date":"2026-09-24","hrv_ms":null,"rhr_bpm":55.5,"sleep_h":7.0,"deep_h":null,"rem_h":1.2,"load_min":0.0}"#
    let d = try JSON.decoder.decode(RecoveryInputDay.self, from: Data(json.utf8))
    #expect(d == RecoveryInputDay(date: "2026-09-24", hrvMs: nil, rhrBpm: 55.5, sleepH: 7, deepH: nil, remH: 1.2, loadMin: 0))
}
