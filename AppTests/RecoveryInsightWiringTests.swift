import Foundation
import Testing
import JICore
import JIFeatures
import JIPersistence
@testable import JournalInsight

// B-57 W3 S4: one RecoveryInsightService per provider, handed to every tab stack (Decide,
// GateRationale, Recovery, KpiDetail pushes all read `\.recoveryInsight`).

@Test @MainActor func mockProviderFeedsTheRecoveryInsight() async throws {
    let provider = MockDataProvider()
    let s = RecoveryInsightService(provider: provider as? any RecoveryInputsProviding,
                                   cache: OfflineCache(db: try AppDatabase.inMemory()),
                                   dayKey: { _ in "2026-09-24" })
    await s.refresh()
    #expect(s.result?.status == .ok)
    #expect(s.result?.score != nil)
}

@Test func tabStackInjectsTheRecoveryInsightAndTheShellResetsIt() throws {
    let src = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "App/RootTabView.swift"), encoding: .utf8)
    let stack = try #require(src.range(of: "private func tabStack<"))
    let tail = String(src[stack.lowerBound...].prefix(1_900))
    #expect(tail.contains(".environment(\\.recoveryInsight, recoveryInsight)"))
    // W-FIX6 F6-11: the insight reads the gate's inputs from the hub (the verdict source).
    #expect(src.contains("recoveryInsight = RecoveryInsightService(provider: verdictSource as? any RecoveryInputsProviding"))
    let invalidate = try #require(src.range(of: "private func invalidateProviderScopedModels()"))
    #expect(String(src[invalidate.lowerBound...].prefix(1_200)).contains("recoveryInsight = nil"))
}
