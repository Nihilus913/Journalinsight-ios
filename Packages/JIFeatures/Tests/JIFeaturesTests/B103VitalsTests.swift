import Foundation
import Testing
import JICore
import JICompute
import JIDesign
import JIPersistence
@testable import JIFeatures

/// W-B103 V-5 (B-103, Bevel REC-7): the phone reads breathing + wrist temp and the hub's
/// `vitals` flag from `/vitals/recovery-inputs`; with the flag on, the score carries the
/// penalty-only `vitals` component (and display-only `temp`). An old hub = no flag = no vitals.

private func body(vitals: Bool?, todayResp: Double) throws -> Data {
    var days: [[String: Any]] = []
    for k in stride(from: 41, through: 0, by: -1) {
        let j = Double(k % 5)
        days.append(["date": try CalendarMath.addDays("2026-10-04", -k), "hrv_ms": 40 + j, "rhr_bpm": 55 + j,
                     "sleep_h": 7 + j / 10, "deep_h": 1, "rem_h": 1.5, "load_min": 30 + j,
                     "resp_bpm": k == 0 ? todayResp : 17 + j / 10, "wrist_temp_c": 36.6])
    }
    var obj: [String: Any] = ["date": "2026-10-04", "days": days]
    if let vitals { obj["vitals"] = vitals }
    return try JSONSerialization.data(withJSONObject: obj)
}

@Test func reportDecodesBreathingTempAndTheVitalsFlag() throws {
    let r = try JSON.decoder.decode(RecoveryInputsReport.self, from: try body(vitals: true, todayResp: 19))
    #expect(r.vitals == true)
    #expect(r.days.last?.respBpm == 19 && r.days.last?.wristTempC == 36.6)
}

@Test func oldHubWithoutTheFlagDecodesAsOff() throws {
    let r = try JSON.decoder.decode(RecoveryInputsReport.self, from: try body(vitals: nil, todayResp: 19))
    #expect(r.vitals == false)
}

@Test func flagOnAddsAPenaltyOnlyVitalsComponent() throws {
    let r = try JSON.decoder.decode(RecoveryInputsReport.self, from: try body(vitals: true, todayResp: 19))
    let on = try #require(RecoveryInsightService.score(days: r.days, today: r.date, vitals: r.vitals))
    let v = try #require(on.component(.vitals))
    #expect(v.status == .ok && (v.z ?? 0) < 0)
    #expect(on.component(.temp)?.status == .calibrating && on.component(.temp)?.z == nil)
    let off = try #require(RecoveryInsightService.score(days: r.days, today: r.date))
    #expect(off.component(.vitals) == nil && off.component(.temp) == nil)
    #expect((on.score ?? 0) < (off.score ?? 0))
}

private nonisolated struct VitalsInputs: RecoveryInputsProviding {
    let report: RecoveryInputsReport
    func recoveryInputs(date: String, windowDays: Int) async throws -> [RecoveryInputDay] { report.days }
    func recoveryInputsReport(date: String, windowDays: Int) async throws -> RecoveryInputsReport { report }
}

@MainActor @Test func serviceMirrorsTheHubFlag() async throws {
    let r = try JSON.decoder.decode(RecoveryInputsReport.self, from: try body(vitals: true, todayResp: 19))
    let s = RecoveryInsightService(provider: VitalsInputs(report: r), cache: OfflineCache(db: try AppDatabase.inMemory()),
                                   now: { Date(timeIntervalSince1970: 0) }, dayKey: { _ in "2026-10-04" })
    await s.refresh()
    #expect(s.result?.component(.vitals)?.status == .ok)
}
