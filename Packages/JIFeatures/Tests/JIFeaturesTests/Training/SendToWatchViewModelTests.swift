#if canImport(WorkoutKit)
import Foundation
import Testing
import WorkoutKit
import JICore
import JIWorkouts
@testable import JIFeatures

/// B-37-L3 (P-workouts) — `SendToWatchViewModel` against `FakeWorkoutSender` + a fake
/// `WorkoutTemplatesProviding`. The builder is injected (`WorkoutBuilder.build` is L2's; the L1 stub
/// throws), so these tests never depend on the real WorkoutKit build.
nonisolated final class FakeTemplatesProvider: WorkoutTemplatesProviding, @unchecked Sendable {
    var rows: [WorkoutTemplate]
    var error: (any Error)?
    init(rows: [WorkoutTemplate], error: (any Error)? = nil) { self.rows = rows; self.error = error }
    func workoutTemplates() async throws -> [WorkoutTemplate] {
        if let error { throw error }
        return rows
    }
}

private func seedRows() async throws -> [WorkoutTemplate] {
    try await MockDataProvider().workoutTemplates()
}

private let fixedNow = ISO8601DateFormatter().date(from: "2026-09-21T08:00:00Z")!

/// A builder that never touches L2's code: one `CustomWorkout` per template, named after it.
private let stubBuilder: SendToWatchViewModel.Builder = { template in
    WorkoutPlan(.custom(CustomWorkout(activity: .running, location: .outdoor, displayName: template.name)))
}

@MainActor
private func makeVM(
    provider: any WorkoutTemplatesProviding,
    sender: FakeWorkoutSender = FakeWorkoutSender(),
    builder: @escaping SendToWatchViewModel.Builder = stubBuilder,
    openSettings: @escaping () -> Void = {}
) -> SendToWatchViewModel {
    SendToWatchViewModel(provider: provider, sender: sender, builder: builder, now: { fixedNow }, openSettings: openSettings)
}

@Test @MainActor func sendToWatchLoadsTemplatesAndDefaultsDateToToday() async throws {
    let vm = makeVM(provider: FakeTemplatesProvider(rows: try await seedRows()))
    #expect(vm.state == .idle)
    await vm.load()
    #expect(vm.state == .idle)
    #expect(vm.templates.count == 4)
    #expect(vm.templates.map(\.name) == ["Long Run Zone 2", "Zone 2 40 min", "Norwegian 4×4", "Zone 2 60 min"])
    #expect(vm.selected.isEmpty)
    #expect(vm.date == fixedNow)
    #expect(vm.canSend == false)
}

@Test @MainActor func sendToWatchMultiSelectToggles() async throws {
    let vm = makeVM(provider: FakeTemplatesProvider(rows: try await seedRows()))
    await vm.load()
    vm.toggle(1); vm.toggle(4)
    #expect(vm.selected == [1, 4])
    #expect(vm.isSelected(1) && vm.isSelected(4) && !vm.isSelected(2))
    #expect(vm.canSend)
    vm.toggle(1)
    #expect(vm.selected == [4])
    vm.toggle(4)
    #expect(vm.selected.isEmpty)
    #expect(vm.canSend == false)
}

@Test @MainActor func sendToWatchSchedulesOncePerSelectionWithThePickedDate() async throws {
    let sender = FakeWorkoutSender()
    let vm = makeVM(provider: FakeTemplatesProvider(rows: try await seedRows()), sender: sender)
    await vm.load()
    vm.toggle(3); vm.toggle(1)   // Norwegian 4×4 + Long Run Zone 2 (template_id 3, 1)
    vm.date = ISO8601DateFormatter().date(from: "2026-09-23T06:30:00Z")!

    await vm.send()

    #expect(vm.state == .sent(2))
    let calls = await sender.calls
    #expect(calls.count == 3)
    #expect(calls.first == .requestAuthorization)
    let dates: [DateComponents] = calls.compactMap { if case .schedule(_, let at) = $0 { at } else { nil } }
    #expect(dates.count == 2)
    let expected = Calendar.current.dateComponents([.year, .month, .day], from: vm.date)
    for at in dates {
        #expect(at.year == expected.year && at.month == expected.month && at.day == expected.day)
    }
    let scheduled = try await sender.scheduledWorkouts()
    #expect(scheduled.count == 2)
    #expect(vm.sentNames == ["Long Run Zone 2", "Norwegian 4×4"])
}

@Test @MainActor func sendToWatchNothingSelectedIsANoOp() async throws {
    let sender = FakeWorkoutSender()
    let vm = makeVM(provider: FakeTemplatesProvider(rows: try await seedRows()), sender: sender)
    await vm.load()
    await vm.send()
    #expect(vm.state == .idle)
    #expect(await sender.calls.isEmpty)
}

@Test @MainActor func sendToWatchAuthDeniedStateAndOpenSettingsHook() async throws {
    let sender = FakeWorkoutSender(authorizationResult: false)
    var opened = 0
    let vm = makeVM(provider: FakeTemplatesProvider(rows: try await seedRows()), sender: sender, openSettings: { opened += 1 })
    await vm.load()
    vm.toggle(1)
    await vm.send()
    #expect(vm.state == .authDenied)
    #expect(await sender.calls == [.requestAuthorization])
    #expect(vm.statusMessage.contains("Settings"))
    vm.openSettings()
    #expect(opened == 1)
}

@Test @MainActor func sendToWatchProviderErrorBecomesErrorState() async {
    let vm = makeVM(provider: FakeTemplatesProvider(rows: [], error: HubError.network("hub down")))
    await vm.load()
    guard case .error(let msg) = vm.state else { Issue.record("expected .error, got \(vm.state)"); return }
    #expect(msg.contains("hub down"))
    #expect(vm.templates.isEmpty)
}

@Test @MainActor func sendToWatchSenderErrorBecomesErrorState() async throws {
    struct Boom: Error {}
    let sender = FakeWorkoutSender(error: Boom())
    let vm = makeVM(provider: FakeTemplatesProvider(rows: try await seedRows()), sender: sender)
    await vm.load()
    vm.toggle(1)
    await vm.send()
    guard case .error = vm.state else { Issue.record("expected .error, got \(vm.state)"); return }
}

@Test @MainActor func sendToWatchBuilderErrorBecomesErrorState() async throws {
    let sender = FakeWorkoutSender()
    let vm = makeVM(provider: FakeTemplatesProvider(rows: try await seedRows()), sender: sender, builder: { _ in throw WorkoutBuilderError.capExceeded(bpm: 180) })
    await vm.load()
    vm.toggle(2)
    await vm.send()
    guard case .error(let msg) = vm.state else { Issue.record("expected .error, got \(vm.state)"); return }
    #expect(msg.contains("175"))
    // Auth was asked, but nothing was scheduled.
    #expect(await sender.calls == [.requestAuthorization])
}
#endif
