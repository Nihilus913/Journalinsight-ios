#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
import JICore
@testable import JIHealthKit

/// Stands in for the L1 compute (`HrvBand` + `appleGateInputs` + `evaluate`) behind the
/// `OnDeviceVerdictComputing` seam: GO when tonight's RMSSD >= 35, else MODIFY; `nil` without a
/// night for the day. Records what it was handed.
final class StubVerdictCompute: OnDeviceVerdictComputing, @unchecked Sendable {
    private(set) var inputs: [OnDeviceVerdictInput] = []
    func compute(_ input: OnDeviceVerdictInput) throws -> OnDeviceVerdictResult? {
        inputs.append(input)
        guard let tonight = input.nights.last(where: { $0.date == input.day && $0.hrvRmssdMs != nil }),
              let hrv = tonight.hrvRmssdMs else { return nil }
        let prior = Set(input.nights.filter { $0.date < input.day && $0.hrvRmssdMs != nil }.map(\.date)).count
        let go = hrv >= 35
        return OnDeviceVerdictResult(
            verdict: go ? "GO — Strength A" : "MODIFY — Z2 only",
            reason: go ? "HRV in band" : "HRV below band",
            sessionPrescription: go ? "Strength A" : "Z2 45 min",
            signals: [GateSignal(key: "hrv", label: "HRV", value: hrv, unit: "ms", threshold: 35, direction: .min, status: go ? .pass : .red, note: nil)],
            baselineNights: min(prior, 28)
        )
    }
}

/// W-ONDEVICE O-7: `HealthKitProvider.morning/morningVerdict` compute on device from the baseline
/// store + HealthKit (Apple only), returning the hub's DTOs; capability ON only with the engine.
@Suite struct HealthKitProviderVerdictTests {
    private let zurich = TimeZone(identifier: "Europe/Zurich")!
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = zurich; return c }
    /// 2026-10-04 06:00 local.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 6))! }
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// Last night (ending 2026-10-04 05:00) with in-sleep native RMSSD `rmssd`.
    private func seedTonight(_ reader: FakeHealthStoreReader, rmssd: Double) throws {
        let sleepType = try #require(HKReadKind.sleepAnalysis.sampleType)
        reader.enqueue(HKAnchoredPage(samples: [
            HKCategorySample(type: sleepType as! HKCategoryType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: at(3, 22), end: at(4, 5)),
        ], deletedObjectIDs: [], newAnchor: nil), for: sleepType)
        guard let rmssdType = HKReadKind.hrvRMSSDQuantityType else { return }
        reader.enqueue(HKAnchoredPage(samples: [
            HKQuantitySample(type: rmssdType, quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: rmssd), start: at(4, 2), end: at(4, 2)),
        ], deletedObjectIDs: [], newAnchor: nil), for: rmssdType)
    }

    private func priorNights(_ n: Int, source: OnDeviceNightSource = .apple) -> [OnDeviceNight] {
        (1...max(1, n)).prefix(n).map { i in
            let d = calendar.date(byAdding: .day, value: -i, to: calendar.startOfDay(for: now))!
            let key = HKSampleWindow(windowDays: 1, now: d, calendar: calendar).days[0]
            return OnDeviceNight(source: source, date: key, hrvRmssdMs: 40, rhrBpm: 50, sleepDurationSec: 27_000)
        }
    }

    private func provider(_ reader: FakeHealthStoreReader, store: FakeBaselineStore, compute: (any OnDeviceVerdictComputing)?) -> HealthKitProvider {
        let fixed = now
        return HealthKitProvider(store: reader, calendar: calendar, now: { fixed }, sourceBundle: { _ in nil },
                                 baseline: store, onDevice: compute)
    }

    @Test func capabilityFlipsOnOnlyWithTheOnDeviceEngine() {
        let off = provider(FakeHealthStoreReader(), store: FakeBaselineStore(), compute: nil)
        #expect(!off.capabilities.contains(.morningVerdict))
        #expect(!off.capabilities.contains(.morning))
        let on = provider(FakeHealthStoreReader(), store: FakeBaselineStore(), compute: StubVerdictCompute())
        #expect(on.capabilities.contains(.morningVerdict))
        #expect(on.capabilities.contains(.morning))
        // The KPI averages (`GateResponse`) need nutrition HealthKit cannot supply: still the hub's.
        #expect(!on.capabilities.contains(.gate))
    }

    @Test func fullNightGivesAGoVerdictInTheHubsDto() async throws {
        guard HKReadKind.hrvRMSSDTypeAvailable else { return }
        let reader = FakeHealthStoreReader()
        try seedTonight(reader, rmssd: 42)
        let store = FakeBaselineStore()
        try store.record(priorNights(28), today: "2026-10-04")
        let compute = StubVerdictCompute()
        let v = try await provider(reader, store: store, compute: compute).morningVerdict(date: "2026-10-04")
        #expect(v.date == "2026-10-04")
        #expect(v.verdict == "GO — Strength A")
        #expect(v.reason == "HRV in band")
        #expect(v.sessionPrescription == "Strength A")
        #expect(v.computedAt == "2026-10-04T04:00:00Z")
        // Tonight's HealthKit night was written to the store before the compute read it.
        #expect(compute.inputs.last?.nights.last == OnDeviceNight(source: .apple, date: "2026-10-04", hrvRmssdMs: 42, sleepDurationSec: 25_200, sleepScore: compute.inputs.last?.nights.last?.sleepScore))
    }

    @Test func lowNightGivesModifyAndMorningCarriesTheSignals() async throws {
        guard HKReadKind.hrvRMSSDTypeAvailable else { return }
        let reader = FakeHealthStoreReader()
        try seedTonight(reader, rmssd: 28)
        let store = FakeBaselineStore()
        try store.record(priorNights(28), today: "2026-10-04")
        let m = try await provider(reader, store: store, compute: StubVerdictCompute()).morning()
        #expect(m.verdict == "MODIFY — Z2 only")
        #expect(m.verdictDate == "2026-10-04")
        #expect(m.isStale == false)
        #expect(m.gateSignals?.first?.value == 28)
        #expect(m.carbs3dAvg == nil)
    }

    /// Toby Q2 (2026-10-04): while calibrating, show the values AND the verdict, labelled.
    @Test func tenNightsShowValuesAndVerdictLabelledCalibrating() async throws {
        guard HKReadKind.hrvRMSSDTypeAvailable else { return }
        let reader = FakeHealthStoreReader()
        try seedTonight(reader, rmssd: 42)
        let store = FakeBaselineStore()
        try store.record(priorNights(10), today: "2026-10-04")
        let p = provider(reader, store: store, compute: StubVerdictCompute())
        let v = try await p.morningVerdict(date: "2026-10-04")
        #expect(v.verdict == "GO — Strength A")
        #expect(v.reason == "Estimate — calibrating (10/28 nights) · HRV in band")
        let m = try await p.morning()
        #expect(m.gateSignals?.first?.value == 42)
        #expect(m.gateSignals?.first?.note == "Estimate — calibrating (10/28 nights)")
    }

    @Test func calibratingLabelText() {
        #expect(OnDeviceVerdictLabel.calibrating(nights: 10) == "Estimate — calibrating (10/28 nights)")
        #expect(OnDeviceVerdictLabel.calibrating(nights: 0) == "Estimate — calibrating (0/28 nights)")
        #expect(OnDeviceVerdictLabel.isCalibrating(nights: 27))
        #expect(!OnDeviceVerdictLabel.isCalibrating(nights: 28))
    }

    @Test func noNightYetIsMissingNeverAGuess() async throws {
        let store = FakeBaselineStore()
        try store.record(priorNights(28), today: "2026-10-04")
        let p = provider(FakeHealthStoreReader(), store: store, compute: StubVerdictCompute())
        await #expect(throws: ProviderError.missing("2026-10-04")) { _ = try await p.morningVerdict(date: "2026-10-04") }
        let m = try await p.morning()
        #expect(m.verdict == nil)
        #expect(m.verdictDate == nil)
        #expect(m.gateSignals == nil)
    }

    // MARK: - The real L1 compute (verifier integration)

    @Test func realEngineFullNightGivesAHubVerdict() async throws {
        guard HKReadKind.hrvRMSSDTypeAvailable else { return }
        let reader = FakeHealthStoreReader()
        try seedTonight(reader, rmssd: 42)
        let store = FakeBaselineStore()
        try store.record(priorNights(28), today: "2026-10-04")
        let p = provider(reader, store: store, compute: JIComputeVerdictEngine())
        let v = try await p.morningVerdict(date: "2026-10-04")
        #expect(["GO", "MODIFY", "MODIFIED", "REDUCED", "REST"].contains { v.verdict.hasPrefix($0) })
        #expect(v.reason?.hasPrefix("Estimate") == false)
        let m = try await p.morning()
        #expect(m.gateSignals?.first { $0.key == "hrv" }?.status == .pass)
    }

    @Test func realEngineTenNightsShowValuesAndVerdictLabelledCalibrating() async throws {
        guard HKReadKind.hrvRMSSDTypeAvailable else { return }
        let reader = FakeHealthStoreReader()
        try seedTonight(reader, rmssd: 42)
        let store = FakeBaselineStore()
        try store.record(priorNights(10), today: "2026-10-04")
        let p = provider(reader, store: store, compute: JIComputeVerdictEngine())
        let v = try await p.morningVerdict(date: "2026-10-04")
        #expect(!v.verdict.isEmpty)
        #expect(v.reason?.hasPrefix("Estimate — calibrating (10/28 nights)") == true)
        let m = try await p.morning()
        let hrv = try #require(m.gateSignals?.first { $0.key == "hrv" })
        #expect(hrv.value == 42)
        #expect(hrv.note?.hasPrefix("Estimate — calibrating (10/28 nights)") == true)
    }

    @Test func realEngineNoNightYetIsMissing() async throws {
        let store = FakeBaselineStore()
        try store.record(priorNights(28), today: "2026-10-04")
        let p = provider(FakeHealthStoreReader(), store: store, compute: JIComputeVerdictEngine())
        await #expect(throws: ProviderError.missing("2026-10-04")) { _ = try await p.morningVerdict(date: "2026-10-04") }
    }

    @Test func withoutTheEngineTheTrioStillRefuses() async {
        let p = provider(FakeHealthStoreReader(), store: FakeBaselineStore(), compute: nil)
        await #expect(throws: ProviderError.notCapable(.gate)) { _ = try await p.morningVerdict(date: "2026-10-04") }
        await #expect(throws: ProviderError.notCapable(.gate)) { _ = try await p.morning() }
    }
}
#endif

#if canImport(HealthKit)
/// W-ONDEVICE O-10: the provider stamps each result with the inputs digest and the night's wake.
@Suite struct OnDeviceShadowStampTests {
    @Test func digestIsStableAndInputSensitive() {
        let a = OnDeviceVerdictInput(day: "2026-10-04", nights: [OnDeviceNight(source: .apple, date: "2026-10-03", hrvRmssdMs: 40)])
        var b = a
        #expect(a.digest == b.digest)
        b.nights[0].hrvRmssdMs = 41
        #expect(a.digest != b.digest)
    }

    @Test func resultCarriesDigestAndWakeTime() async throws {
        guard let rmssdType = HKReadKind.hrvRMSSDQuantityType else { return }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        func at(_ d: Int, _ h: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))! }
        let reader = FakeHealthStoreReader()
        let sleepType = HKReadKind.sleepAnalysis.sampleType!
        let night = HKCategorySample(type: sleepType as! HKCategoryType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: at(3, 22), end: at(4, 5))
        // Two sleep reads: the refresh, then the wake-time read.
        reader.enqueue(HKAnchoredPage(samples: [night], deletedObjectIDs: [], newAnchor: nil), for: sleepType)
        reader.enqueue(HKAnchoredPage(samples: [night], deletedObjectIDs: [], newAnchor: nil), for: sleepType)
        reader.enqueue(HKAnchoredPage(samples: [
            HKQuantitySample(type: rmssdType, quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: 40), start: at(4, 2), end: at(4, 2)),
        ], deletedObjectIDs: [], newAnchor: nil), for: rmssdType)
        let fixed = at(4, 6)
        let p = HealthKitProvider(store: reader, calendar: cal, now: { fixed }, sourceBundle: { _ in nil },
                                  baseline: FakeBaselineStore(), onDevice: StubVerdictCompute())
        let r = try #require(try await p.onDeviceVerdict(day: "2026-10-04"))
        #expect(r.wakeAt == at(4, 5))
        #expect(r.inputsDigest?.isEmpty == false)
    }
}
#endif
