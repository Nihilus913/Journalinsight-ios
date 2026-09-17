import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

@MainActor
private func makeVM(provider: WeighInFakeProvider = WeighInFakeProvider(), db: AppDatabase? = nil) throws -> (WeighInViewModel, Outbox) {
    let outbox = Outbox(db: try db ?? AppDatabase.inMemory())
    return (WeighInViewModel(outbox: outbox, provider: provider), outbox)
}

@Test @MainActor func submitEnqueuesFirstThenConfirmsOnSuccess() async throws {
    let (vm, outbox) = try makeVM()
    let ok = await vm.submit(weightKg: 82.5, date: "2026-09-17")
    #expect(ok)
    guard case .success(let result) = vm.state else { Issue.record("expected success"); return }
    #expect(result.weightKg == 82.5)
    #expect(try outbox.pending().isEmpty) // delivered — retired from the outbox
}

@Test @MainActor func submitQueuesOnNetworkFailureRatherThanFailing() async throws {
    let provider = WeighInFakeProvider()
    provider.error = .network("offline")
    let (vm, outbox) = try makeVM(provider: provider)

    let ok = await vm.submit(weightKg: 82.5)

    #expect(ok) // queued is not a user-facing failure
    #expect(vm.state == .queued)
    #expect(try outbox.pending().count == 1) // row survives, ready for a later retry
}

@Test @MainActor func submitSurfacesHubDetailVerbatimOn502() async throws {
    let provider = WeighInFakeProvider()
    provider.error = .yazioAuthExpired(detail: "Garmin FIT upload rejected")
    let (vm, _) = try makeVM(provider: provider)

    let ok = await vm.submit(weightKg: 82.5)

    #expect(!ok)
    #expect(vm.state == .failure("Garmin FIT upload rejected"))
}
