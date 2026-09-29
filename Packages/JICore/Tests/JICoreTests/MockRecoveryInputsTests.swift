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

// MARK: - W-FIX10 R-04: the hub's DH-4 calibration block

@Test func recoveryInputsReportDecodesTheCalibrationBlock() throws {
    let json = #"""
    {"date":"2026-09-29","days":[],"calibration":{"status":"calibrating","calibrating":true,"nights":4,
     "nights_needed":14,"components":{"hrv":{"status":"calibrating","nights":4},"rhr":{"status":"calibrating","nights":10},
     "sleep":{"status":"calibrating","nights":10},"load":{"status":"ok","nights":28}}}}
    """#
    let r = try JSON.decoder.decode(RecoveryInputsReport.self, from: Data(json.utf8))
    let c = try #require(r.calibration)
    #expect(c.calibrating && c.status == "calibrating")
    #expect(c.nights == 4 && c.nightsNeeded == 14)
    #expect(c.component("rhr") == RecoveryCalibrationComponent(status: "calibrating", nights: 10))
    #expect(c.isCalibrating("hrv") && !c.isCalibrating("load") && !c.isCalibrating("nope"))
}

@Test func recoveryInputsReportFromAnOlderHubHasNoCalibration() throws {
    let r = try JSON.decoder.decode(RecoveryInputsReport.self, from: Data(#"{"date":"2026-09-29","days":[]}"#.utf8))
    #expect(r.calibration == nil)
}

@Test func mockReportCarriesASettledBaseline() async throws {
    let r = try await MockDataProvider().recoveryInputsReport(date: "2026-09-24", windowDays: 42)
    #expect(r.days.count == 42)
    #expect(r.calibration?.calibrating == false)
    #expect(MockDataProvider.recoveryCalibration(nights: 4).isCalibrating("hrv"))
}
