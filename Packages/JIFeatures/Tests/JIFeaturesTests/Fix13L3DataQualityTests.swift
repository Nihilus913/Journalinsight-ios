import Foundation
import Testing
import JICore
@testable import JIFeatures

/// W-FIX13 F-5 (B-59) — Settings › Sync & hub › Data quality never sits on the placeholder: the
/// loader resolves to `.loaded`, or fails with a Retry that resolves.
private final class ScriptedDataQualityProvider: DataQualityProviding, @unchecked Sendable { // @unchecked: tests drive it from the main actor only
    enum Step { case report(DataQualityReport), fail(HubError), hang }
    var steps: [Step]
    private(set) var calls = 0
    init(_ steps: [Step]) { self.steps = steps }
    func dataQuality() async throws -> DataQualityReport {
        calls += 1
        let step = steps.count > 1 ? steps.removeFirst() : steps[0]
        switch step {
        case .report(let r): return r
        case .fail(let e): throw e
        case .hang:
            try await Task.sleep(for: .seconds(3600))
            throw CancellationError()
        }
    }
}

@MainActor @Suite struct Fix13L3DataQualityTests {
    func report() async throws -> DataQualityReport { try await MockDataProvider().dataQuality() }

    @Test func providerAnswersIsLoaded() async throws {
        let model = DataQualityViewModel(provider: ScriptedDataQualityProvider([.report(try await report())]))
        await model.load()
        #expect(model.phase == .loaded)
        #expect(!model.isFailed)
        #expect(!model.sourceSummary.sources.isEmpty)   // per-source rows
    }

    @Test func providerThrowsIsFailedAndRetryLoads() async throws {
        let provider = ScriptedDataQualityProvider([.fail(.network("offline")), .report(try await report())])
        let model = DataQualityViewModel(provider: provider)
        await model.load()
        #expect(model.isFailed)
        #expect(model.canRetry)
        await model.retry()
        #expect(model.phase == .loaded)
        #expect(!model.isFailed)
        #expect(provider.calls == 2)
    }

    @Test func aHubThatNeverAnswersEndsInAFailureNotAnEndlessPlaceholder() async {
        let model = DataQualityViewModel(provider: ScriptedDataQualityProvider([.hang]), timeout: .milliseconds(50))
        await model.load()
        #expect(model.isFailed)
        #expect(model.phase == .error("The hub didn't answer in time."))
    }

    @Test func aCancelledLoadIsReloadedWhenTheScreenAppearsAgain() async throws {
        let provider = ScriptedDataQualityProvider([.hang, .report(try await report())])
        let model = DataQualityViewModel(provider: provider)
        let first = Task { await model.load() }
        try await Task.sleep(for: .milliseconds(20))
        first.cancel()
        await first.value
        #expect(model.phase == .idle)
        #expect(DataQualityView.needsLoad(model))   // the screen's task loads again on appear
        await model.load()
        #expect(model.phase == .loaded)
        #expect(!DataQualityView.needsLoad(model))
    }
}
