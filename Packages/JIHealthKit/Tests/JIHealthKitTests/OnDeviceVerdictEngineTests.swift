import Foundation
import Testing
import JICore
import JICompute
@testable import JIHealthKit

/// W-ONDEVICE verifier integration: the real L1 compute (`mergeRecoveryDays` + `HrvBand` +
/// `AppleGate` + `evaluate`) behind the L2 `OnDeviceVerdictComputing` seam.
@Suite struct OnDeviceVerdictEngineTests {
    private let engine = JIComputeVerdictEngine()
    private let today = "2026-10-04"

    private func day(_ offset: Int) -> String { try! CalendarMath.addDays(today, offset) }

    /// `n` prior nights (oldest first) of `source`, RMSSD wobbling around 40 ms.
    private func prior(_ n: Int, source: OnDeviceNightSource = .apple, from start: Int = 1) -> [OnDeviceNight] {
        guard n > 0 else { return [] }
        return (start..<(start + n)).reversed().map { i in
            OnDeviceNight(source: source, date: day(-i), hrvRmssdMs: 38 + Double(i % 5), rhrBpm: 50,
                          sleepDurationSec: 7.5 * 3600, sleepScore: 80)
        }
    }

    private func tonight(rmssd: Double, sleepH: Double = 7.6) -> OnDeviceNight {
        OnDeviceNight(source: .apple, date: today, hrvRmssdMs: rmssd, rhrBpm: 49, sleepDurationSec: sleepH * 3600, sleepScore: 82)
    }

    @Test func noNightForTheDayIsMissingNotAGuess() throws {
        let r = try engine.compute(OnDeviceVerdictInput(day: today, nights: prior(30)))
        #expect(r == nil)
    }

    @Test func fullBaselineNightGivesTheEvaluateVerdict() throws {
        let nights = prior(28) + [tonight(rmssd: 40)]
        let r = try #require(try engine.compute(OnDeviceVerdictInput(day: today, nights: nights)))
        #expect(r.baselineNights == 28)
        #expect(!OnDeviceVerdictLabel.isCalibrating(nights: r.baselineNights))
        // Same verdict as calling JICompute directly with the hub's Apple-night shape.
        let band = try HrvBand.compute(apple: Dictionary(uniqueKeysWithValues: nights.map { ($0.date, $0.hrvRmssdMs!) }), today: today)
        #expect(band.status == .pass)
        let hrv = try #require(r.signals.first { $0.key == "hrv" })
        #expect(hrv.status == .pass)
        #expect(hrv.bandMethod == AppleGate.hrvBandMethod)
        #expect(r.signals.contains { $0.key == "sleep_h" })
        #expect(r.signals.contains { $0.key == "recovery" })
        #expect(["GO", "MODIFY", "MODIFIED", "REDUCED", "REST"].contains { r.verdict.hasPrefix($0) })
        #expect(r.sessionPrescription == (try sessionFor(today).name))
        #expect(r.reason != nil && !(r.reason ?? "").isEmpty)
    }

    @Test func lowHrvNightIsNotGo() throws {
        let nights = prior(28) + [tonight(rmssd: 22)]
        let r = try #require(try engine.compute(OnDeviceVerdictInput(day: today, nights: nights)))
        #expect(!r.verdict.hasPrefix("GO"))
        #expect(r.signals.first { $0.key == "hrv" }?.status == .amber)
    }

    @Test func tenNightsIsCalibratingWithValuesAndLabel() throws {
        let nights = prior(10) + [tonight(rmssd: 41)]
        let r = try #require(try engine.compute(OnDeviceVerdictInput(day: today, nights: nights)))
        #expect(r.baselineNights == 10)
        #expect(OnDeviceVerdictLabel.reason(r)?.hasPrefix("Estimate — calibrating (10/28 nights)") == true)
        // W-CAL C-4: tonight's value stays visible while calibrating.
        #expect(r.signals.first { $0.key == "hrv" }?.value == 41)
    }

    @Test func hubSeededGarminNightsCompleteTheBaseline() throws {
        let nights = prior(120, source: .garmin) + [tonight(rmssd: 40)]
        let r = try #require(try engine.compute(OnDeviceVerdictInput(day: today, nights: nights)))
        #expect(r.baselineNights == 28)
        #expect(!OnDeviceVerdictLabel.isCalibrating(nights: r.baselineNights))
    }

    @Test func headlineLeadsWithTheCalibratingLabel() throws {
        let cal = try #require(try engine.compute(OnDeviceVerdictInput(day: today, nights: prior(10) + [tonight(rmssd: 41)])))
        #expect(OnDeviceVerdictLabel.headline(cal) == "Estimate — calibrating (10/28 nights) · \(cal.verdict)")
        let full = try #require(try engine.compute(OnDeviceVerdictInput(day: today, nights: prior(28) + [tonight(rmssd: 41)])))
        #expect(OnDeviceVerdictLabel.headline(full) == full.verdict)
    }

    @Test func labelUsesTheL1BaselineConstant() {
        #expect(OnDeviceVerdictLabel.baselineNights == HrvBand.baselineNights)
    }

    @Test func budgetFor120DaysTwoSourcesIsUnderTwoSeconds() throws {
        let nights = prior(120) + prior(120, source: .garmin) + [tonight(rmssd: 41)]
        let clock = ContinuousClock()
        let elapsed = try clock.measure { _ = try engine.compute(OnDeviceVerdictInput(day: today, nights: nights)) }
        #expect(elapsed < .seconds(2))
    }
}
