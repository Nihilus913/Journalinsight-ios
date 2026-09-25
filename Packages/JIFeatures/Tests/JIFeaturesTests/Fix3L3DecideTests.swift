import Foundation
import SwiftUI
import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-FIX3 L3 — BUG-30 (Decide vs board 01), C-d (Trends HRV role), C-f (Decide's synced pill).
struct Fix3L3DecideTests {
    private func s(_ key: String, _ label: String, _ value: Double?, thr: Double, unit: String = "",
                   dir: GateSignalDirection = .min, status: GateSignalStatus, note: String? = nil) -> GateSignal {
        GateSignal(key: key, label: label, value: value, unit: unit, threshold: thr, direction: dir,
                   scaleMin: 0, scaleMax: 100, status: status, note: note)
    }

    /// 28 nights of RMSSD around 28.5 ms, plus last night (the one being judged, 24 ms).
    private func nights(hrv: [Double], rhr: [Double]? = nil) -> [RecoveryDay] {
        hrv.enumerated().map { i, v in
            let d = Calendar(identifier: .gregorian).date(byAdding: .day, value: i, to: Date(timeIntervalSince1970: 1_786_406_400))!
            return RecoveryDay(date: String(d.ISO8601Format().prefix(10)), rhrBpm: rhr?[i], hrvRmssdMs: v)
        }
    }

    // MARK: BUG-30 labels

    @Test func restingHRIsSpelledOutAndHRVIsTheNightsValue() {
        #expect(decideSignalLabel(s("rhr", "RHR", 52, thr: 65, status: .pass)) == "Resting HR")
        #expect(decideSignalLabel(s("hrv", "HRV", 25, thr: 27, status: .amber)) == "Overnight HRV")
        // an Apple night's 7-day HRV keeps its honest label
        #expect(decideSignalLabel(s("hrv", "HRV (7-day)", 46, thr: 41, status: .pass)) == "HRV (7-day)")
        #expect(decideSignalLabel(s("hrv_day", "HRV (day)", 31, thr: 0, status: .context)) == "Daytime HRV")
    }

    // MARK: BUG-30 reference line: "your normal a–b" / "goal 7 h", never "threshold" / "floor"

    @Test func sleepTimeReadsAsAGoal() {
        let m = decideSignalRowModel(s("sleep_h", "Sleep time", 7.4, thr: 7, unit: "h", status: .pass))
        #expect(m.detail == "goal 7 h")
        #expect(m.status == .aboveGoal)
        let short = decideSignalRowModel(s("sleep_h", "Sleep time", 6.2, thr: 7, unit: "h", status: .amber))
        #expect(short.status == .belowGoal)
        #expect(decideSignalRowModel(s("sleep_h", "Sleep time", 6.2, thr: 6.5, unit: "h", status: .amber)).detail == "goal 6.5 h")
    }

    @Test func aPersonalNormalReplacesTheThreshold() {
        let m = decideSignalRowModel(s("hrv", "HRV", 25, thr: 27, unit: "ms", status: .amber), normal: 27...30)
        #expect(m.normal == 27...30)
        #expect(m.detail == nil)
        #expect(signalReferenceText(normal: m.normal, goal: nil, unit: m.unit, decimals: m.decimals, detail: m.detail) == "your normal 27–30")
    }

    @Test func noNormalYetSaysCalibratingNeverThreshold() {
        for sig in [s("hrv", "HRV", 25, thr: 27, unit: "ms", status: .amber), s("rhr", "RHR", 52, thr: 65, unit: "bpm", dir: .max, status: .pass),
                    s("sleep", "Sleep", 74, thr: 70, status: .pass)] {
            let d = decideSignalRowModel(sig).detail ?? ""
            #expect(d == "your normal — Calibrating")
            #expect(!d.contains("threshold"))
        }
    }

    @Test func missingValueSaysNoOvernightValueYet() {
        let m = decideSignalRowModel(s("rhr", "RHR", nil, thr: 65, unit: "bpm", dir: .max, status: .missing))
        #expect(m.status == .missing(.noData))
        #expect(m.detail == "no overnight value yet")
    }

    @Test func theHubsOwnBandIsTheNormalOnAppleNights() {
        let sig = s("hrv", "HRV (7-day)", 46, thr: 41, unit: "ms", status: .pass, note: "band 41–52 ms")
        #expect(decideSignalRowModel(sig).normal == 41...52)
    }

    @Test func personalNormalIsMedianPlusMinusScaledMAD() {
        // 28 prior nights alternating 27 / 30 → median 28.5, MAD 1.5 → 28.5 ± 2.2 → 26–31 (rounded)
        let prior = (0..<28).map { $0 % 2 == 0 ? 27.0 : 30.0 }
        let normals = decideSignalNormals(recovery: nights(hrv: prior + [24]))
        let hrv = try! #require(normals["hrv"])
        #expect(hrv.lowerBound == 26 && hrv.upperBound == 31)
    }

    @Test func tooFewNightsIsNoNormal() {
        #expect(decideSignalNormals(recovery: nights(hrv: [27, 28, 29, 30, 24]))["hrv"] == nil)
    }

    @Test func lastNightIsNotPartOfItsOwnNormal() {
        // 14 prior nights at 30 and last night at 10: the normal stays 30–30, not dragged down.
        let normals = decideSignalNormals(recovery: nights(hrv: Array(repeating: 30, count: 14) + [10]))
        #expect(normals["hrv"] == 30...30)
    }

    // MARK: BUG-30 Go is black on green; no second title on Decide

    @Test func goLabelIsBlackOnTheGreenButton() {
        #expect(decideGoForeground == Color.black)
    }

    @Test func decideHasNoPageTitleDayKeepsIt() {
        #expect(todayNavigationTitle(state: .decide, pageName: "Today") == "")
        #expect(todayNavigationSubtitleShown(state: .decide) == false)
        #expect(todayNavigationTitle(state: .day, pageName: "Today") == "Today")
        #expect(todayNavigationTitle(state: .coach, pageName: "My day") == "My day")
        #expect(todayNavigationSubtitleShown(state: .day))
    }

    // MARK: C-d

    @Test func trendsHRVUsesTheHRVRoleNotTheAccent() {
        let hrv = todayTrends(recovery: [], daily: []).first { $0.id == "hrv" }
        #expect(hrv?.colorRole == .hrv)
    }

    // MARK: C-f

    @Test @MainActor func decidesPillIsTheSyncTimeNotTheFetchTime() {
        let synced = Date(timeIntervalSince1970: 1_790_000_000)
        let view = DecideView(verdict: verdictParts("GO — Full Upper"), readiness: nil, syncing: false, gateSignals: nil,
                              verdictDate: "2026-09-25", sessionForToday: nil, override: nil, overrideModel: nil,
                              syncedAt: synced) {}
        #expect(view.syncedAt == synced)
    }
}
