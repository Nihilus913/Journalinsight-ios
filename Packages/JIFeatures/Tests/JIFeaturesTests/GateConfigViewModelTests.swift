import Foundation
import Testing
import JICore
import JICompute
import JIHub
import JIPersistence
@testable import JIFeatures

// W5b-L3 (P-gate-config). `GateConfigViewModel` against an in-memory `PrefStore` and either the
// `MockDataProvider` (fixture KPI targets) or a real `HubDataProvider` behind a stub `URLProtocol`
// (card exit criterion: "KPI rule edits PUT via the existing provider (stub-URLProtocol test)").

@MainActor
private func makeModel(provider: (any KpiTargetsProviding)? = MockDataProvider()) throws -> (GateConfigViewModel, PrefStore) {
    let store = PrefStore(db: try AppDatabase.inMemory())
    return (GateConfigViewModel(targetsProvider: provider, prefStore: store), store)
}

// MARK: - Morning-gate overrides + preview

@Test @MainActor func freshModelShowsCompiledDefaultsAndTheBaselineVerdict() async throws {
    let (vm, _) = try makeModel()
    await vm.load()
    #expect(vm.loaded)
    #expect(vm.effectiveConfig == MorningGateConfig.default)
    #expect(vm.value(for: .minSleepH) == 6.0)
    #expect(vm.previewWithOverrides.verdict == "GO — Norwegian 4x4 intervals")
    #expect(GateConfigViewModel.baselinePreview.verdict == "GO — Norwegian 4x4 intervals")
    #expect(vm.verdictFlipped == false)
}

/// The E12-8 acceptance, at the screen's layer: one "+" on Min sleep (6.0 → 6.5) crosses the
/// fixture day's 6.2 h and the preview flips exactly as the ported compute test expects.
@Test @MainActor func oneStepUpOnMinSleepFlipsThePreviewVerdict() async throws {
    let (vm, _) = try makeModel()
    await vm.load()
    vm.bump(.minSleepH, direction: 1)
    #expect(vm.value(for: .minSleepH) == 6.5)
    #expect(vm.isOverridden(.minSleepH))
    #expect(vm.previewWithOverrides.verdict == "MODIFIED — swap intervals for easy Z2 30-40min")
    #expect(vm.verdictFlipped)
    #expect(vm.previewWithOverrides.conditions.joined(separator: " ").contains("Interval gate failed"))
}

@Test @MainActor func rapidTapsAccumulateInsteadOfOverwriting() async throws {
    let (vm, _) = try makeModel()
    await vm.load()
    vm.bump(.stepTarget, direction: 1)
    vm.bump(.stepTarget, direction: 1)
    vm.bump(.stepTarget, direction: 1)
    #expect(vm.value(for: .stepTarget) == 16500)
    #expect(vm.effectiveConfig.stepTarget == 16500)
}

@Test @MainActor func bumpClampsAtTheFieldFloor() async throws {
    let (vm, _) = try makeModel()
    await vm.load()
    for _ in 0..<20 { vm.bump(.minSleepH, direction: -1) }
    #expect(vm.value(for: .minSleepH) == 0)
}

@Test @MainActor func resetOneFieldRestoresItsDefaultAndDropsTheOverride() async throws {
    let (vm, _) = try makeModel()
    await vm.load()
    vm.bump(.minSleepH, direction: 1)
    vm.bump(.targetBf, direction: -1)
    vm.reset(.minSleepH)
    #expect(vm.isOverridden(.minSleepH) == false)
    #expect(vm.value(for: .minSleepH) == 6.0)
    #expect(vm.isOverridden(.targetBf))
    #expect(vm.verdictFlipped == false)
}

/// Card exit criterion: "defaults reset restores `DEFAULT_MORNING_GATE_CONFIG`".
@Test @MainActor func resetAllRestoresDefaultMorningGateConfigAndClearsTheStore() async throws {
    let (vm, store) = try makeModel()
    await vm.load()
    for field in MorningGateOverridableField.allCases { vm.bump(field, direction: 1) }
    #expect(vm.effectiveConfig != MorningGateConfig.default)
    vm.resetAllMorning()
    #expect(vm.effectiveConfig == MorningGateConfig.default)
    #expect(vm.morningOverrides.isEmpty)
    let stored: MorningGateOverrides?? = try? store.get(GateConfigViewModel.morningOverridesKey, as: MorningGateOverrides.self)
    #expect((stored ?? nil) == nil)
}

@Test @MainActor func overridesPersistAcrossViewModelInstancesUnderRnKey() async throws {
    let (vm, store) = try makeModel()
    await vm.load()
    vm.bump(.minSleepH, direction: 1)
    let raw: MorningGateOverrides?? = try store.get("config_overrides.morning_gate", as: MorningGateOverrides.self)
    #expect((raw ?? nil)?[.minSleepH] == 6.5)

    let vm2 = GateConfigViewModel(targetsProvider: nil, prefStore: store)
    vm2.loadLocal()
    #expect(vm2.value(for: .minSleepH) == 6.5)
    #expect(vm2.verdictFlipped)
}

// MARK: - KPI rule overrides (local)

@Test @MainActor func kpiRuleBumpUsesTheOracleStepAndPersists() async throws {
    let (vm, store) = try makeModel()
    await vm.load()
    let acwrHigh = try #require(defaultKpiRules.first { kpiRuleKey($0) == "acwr:>" })
    vm.bumpKpi(acwrHigh, direction: 1)
    #expect(vm.kpiThreshold(for: acwrHigh) == 1.35)
    #expect(vm.isKpiOverridden("acwr:>"))
    let raw: KpiRuleOverrides?? = try store.get("config_overrides.kpi_rules", as: KpiRuleOverrides.self)
    #expect((raw ?? nil)?["acwr:>"]?.threshold == 1.35)
    vm.resetKpi("acwr:>")
    #expect(vm.previewKpiRules == defaultKpiRules)
}

// MARK: - Server KPI targets (live, via the EXISTING KpiTargetsProviding)

@Test @MainActor func serverTargetsLoadFromTheProvider() async throws {
    let (vm, _) = try makeModel()
    await vm.load()
    #expect(vm.hasServerProvider)
    #expect(vm.serverPhase == .loaded)
    #expect(vm.serverTargets.isEmpty == false)
}

@Test @MainActor func noProviderLeavesTheServerBlockIdleButLocalBlocksWork() async throws {
    let (vm, _) = try makeModel(provider: nil)
    await vm.load()
    #expect(vm.hasServerProvider == false)
    #expect(vm.serverPhase == .idle)
    #expect(vm.loaded)
    vm.bump(.minSleepH, direction: 1)
    #expect(vm.verdictFlipped)
}

/// Serves canned responses keyed by path and records the last request. Its own class (not
/// JIHub's test-target `StubURLProtocol`) because test targets cannot share sources.
final class GateConfigStubURLProtocol: URLProtocol, @unchecked Sendable { // @unchecked: static state guarded by the serialized suite
    nonisolated(unsafe) static var responses: [String: (Int, Data)] = [:]
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        var body = Data()
        if let stream = request.httpBodyStream {
            stream.open()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate(); stream.close() }
            while stream.hasBytesAvailable {
                let n = stream.read(buffer, maxLength: 4096)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
        } else if let b = request.httpBody { body = b }
        Self.bodies.append(body)
        let path = request.url!.path
        let (status, data) = Self.responses[path] ?? (404, Data("{\"detail\":\"not found\"}".utf8))
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [GateConfigStubURLProtocol.self]
        return URLSession(configuration: c)
    }

    static func reset() { responses = [:]; requests = []; bodies = [] }
}

@Suite(.serialized) struct GateConfigServerPutTests {
    private static let listJSON = Data("""
    {"targets":[{"target_id":6,"metric":"acwr","operator":">","threshold":1.3,"threshold_hi":null,"description":"REDUCE: overreaching risk"},
                {"target_id":7,"metric":"avg_kcal_7d","operator":"<","threshold":1600.0,"threshold_hi":null,"description":"REDUCE: chronic underfueling"}]}
    """.utf8)

    private func hubProvider() -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k")
        return HubDataProvider(client: HubClient(config: config, session: GateConfigStubURLProtocol.session()))
    }

    /// Card exit criterion: "KPI rule edits PUT via the existing provider (stub-URLProtocol test)".
    @Test @MainActor func nudgeSendsPutToTheRouterPathWithBearerAndSnakeCaseBodyAndWritesBackTheServerRow() async throws {
        GateConfigStubURLProtocol.reset()
        GateConfigStubURLProtocol.responses["/api/v1/planning/kpi-targets"] = (200, Self.listJSON)
        GateConfigStubURLProtocol.responses["/api/v1/planning/kpi-targets/6"] = (200, Data("""
        {"target_id":6,"metric":"acwr","operator":">","threshold":1.35,"threshold_hi":null,"description":"REDUCE: overreaching risk"}
        """.utf8))
        let vm = GateConfigViewModel(targetsProvider: hubProvider(), prefStore: PrefStore(db: try AppDatabase.inMemory()))
        await vm.load()
        #expect(vm.serverPhase == .loaded)
        let acwr = try #require(vm.serverTargets.first { $0.targetId == 6 })

        await vm.nudgeServer(acwr, direction: 1)

        let put = try #require(GateConfigStubURLProtocol.requests.last)
        #expect(put.httpMethod == "PUT")
        #expect(put.url?.path == "/api/v1/planning/kpi-targets/6") // app/planning/router.py:711
        #expect(put.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
        #expect(put.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(GateConfigStubURLProtocol.bodies.last)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect((json["threshold"] as? Double) == 1.35)
        #expect(json.keys.contains("description"))
        #expect(Set(json.keys).isSubset(of: ["threshold", "threshold_hi", "description"])) // KpiTargetUpdate extra="forbid"
        #expect(vm.serverTargets.first { $0.targetId == 6 }?.threshold == 1.35)
        #expect(vm.serverSaveError == nil)
    }

    @Test @MainActor func failedPutRollsBackAndSurfacesTheHubDetail() async throws {
        GateConfigStubURLProtocol.reset()
        GateConfigStubURLProtocol.responses["/api/v1/planning/kpi-targets"] = (200, Self.listJSON)
        GateConfigStubURLProtocol.responses["/api/v1/planning/kpi-targets/7"] = (422, Data("{\"detail\":\"threshold_hi must exceed threshold\"}".utf8))
        let vm = GateConfigViewModel(targetsProvider: hubProvider(), prefStore: PrefStore(db: try AppDatabase.inMemory()))
        await vm.load()
        let kcal = try #require(vm.serverTargets.first { $0.targetId == 7 })

        await vm.nudgeServer(kcal, direction: -1)

        #expect(vm.serverTargets.first { $0.targetId == 7 }?.threshold == 1600.0) // exact rollback
        let message = try #require(vm.serverSaveError)
        #expect(message.hasPrefix("Couldn't save — reverted."))
        #expect(message.contains("threshold_hi must exceed threshold"))
    }

    @Test @MainActor func kcalStepIs25AndAcwrStepIs005OnTheServerRows() async throws {
        GateConfigStubURLProtocol.reset()
        GateConfigStubURLProtocol.responses["/api/v1/planning/kpi-targets"] = (200, Self.listJSON)
        GateConfigStubURLProtocol.responses["/api/v1/planning/kpi-targets/7"] = (200, Data("""
        {"target_id":7,"metric":"avg_kcal_7d","operator":"<","threshold":1625.0,"threshold_hi":null,"description":"REDUCE: chronic underfueling"}
        """.utf8))
        let vm = GateConfigViewModel(targetsProvider: hubProvider(), prefStore: PrefStore(db: try AppDatabase.inMemory()))
        await vm.load()
        let kcal = try #require(vm.serverTargets.first { $0.targetId == 7 })
        await vm.nudgeServer(kcal, direction: 1)
        let body = try #require(GateConfigStubURLProtocol.bodies.last)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect((json["threshold"] as? Double) == 1625)
    }
}
