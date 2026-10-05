import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// B-52 p4: the training break and Push to Garmin are outbox kinds — hub down → queued + shown
/// pending, hub up → the launch-registered drainer delivers them (once, last-write-wins).
private actor BreakHub: TrainingBreakProviding {
    var up = false
    var stored = TrainingBreak(paused: false)
    var calls: [TrainingBreak] = []
    func setUp(_ u: Bool) { up = u }
    func trainingBreak() async throws -> TrainingBreak {
        guard up else { throw HubError.network("offline") }
        return stored
    }
    func setTrainingBreak(paused: Bool, since: String?) async throws -> TrainingBreak {
        guard up else { throw HubError.network("offline") }
        calls.append(TrainingBreak(paused: paused, since: since))
        stored = TrainingBreak(paused: paused, since: paused ? since : nil)
        return stored
    }
}

private let oct5 = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!

@MainActor
private func launchDrainer(_ outbox: Outbox, hub: any Sendable) -> OutboxDrainer {
    let registry = OutboxFirstRegistry()
    B52WriteKinds.registerAll(in: registry, hub: { hub })
    return OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, registry: registry)
}

@MainActor @Suite struct B52P4WritesTests {
    @Test func b52p4_kindsAreRegisteredNotBuiltIn() {
        let registry = OutboxFirstRegistry()
        B52WriteKinds.registerAll(in: registry, hub: { nil })
        #expect(registry.kinds == ["training_break", "garmin_push"])
        #expect(OutboxDrainer.knownKinds.isDisjoint(with: registry.kinds))
    }

    @Test func b52p4_breakTogglesOfflineQueueAndOnlyTheNewestLands() async throws {
        let outbox = Outbox(db: try AppDatabase.inMemory())
        let hub = BreakHub()
        let m = TrainingBreakViewModel(provider: hub, state: TrainingBreak(paused: false), outbox: outbox, now: { oct5 })
        await m.set(paused: true)
        await m.set(paused: false)
        await m.set(paused: true)
        #expect(m.paused && m.pending && m.errorMessage == nil)
        #expect(try outbox.pending().filter { $0.kind == "training_break" }.count == 3)

        // A relaunch (fresh model, hub still down) shows the queued state, not the cached one.
        let relaunched = TrainingBreakViewModel(provider: hub, state: nil, outbox: outbox, now: { oct5 })
        #expect(relaunched.paused && relaunched.pending)

        await hub.setUp(true)
        _ = await launchDrainer(outbox, hub: hub).drainOnce()
        #expect(await hub.calls == [TrainingBreak(paused: true, since: "2026-10-05")], "last-write-wins: one PUT")
        #expect(try outbox.pending().isEmpty)
        await relaunched.load()
        #expect(relaunched.paused && !relaunched.pending && relaunched.sinceText == "On a break since 5 Oct")
    }

    @Test func b52p4_breakDeliversInTheTapWhenTheHubIsUp() async throws {
        let outbox = Outbox(db: try AppDatabase.inMemory())
        let hub = BreakHub()
        await hub.setUp(true)
        var fired = 0
        let m = TrainingBreakViewModel(provider: hub, state: TrainingBreak(paused: false), outbox: outbox,
                                       now: { oct5 }, onChanged: { fired += 1 })
        await m.set(paused: true)
        #expect(m.paused && !m.pending && fired == 1)
        #expect(try outbox.pending().isEmpty)
    }

    @Test func b52p4_pushQueuesOfflineAndTheDrainerDeliversItOnce() async throws {
        let db = try AppDatabase.inMemory()
        let outbox = Outbox(db: db)
        let row = WorkoutTemplate(templateId: 7, name: "Zone 2", activity: "running", location: .outdoor, weekdays: [], steps: [],
                                  updatedAt: "2026-10-05T08:00:00Z",
                                  segments: [WorkoutSegment(sport: .running, steps: [.cardio(CardioStep(purpose: .work, end: .time(seconds: 1800), target: .none))])])
        let hub = FakeWorkoutHub(rows: [row])
        let vm = WorkoutLibraryViewModel(provider: hub, cache: OfflineCache(db: db), outbox: outbox)
        await vm.load()
        hub.readsFail = true
        hub.garminError = HubError.network("offline")
        await vm.pushToGarmin(vm.templates[0])
        await vm.pushToGarmin(vm.templates[0])   // blocked: already queued
        #expect(vm.pendingPushIds == [7])
        #expect(try outbox.pending().filter { $0.kind == "garmin_push" }.count == 1)
        #expect(!vm.hubReachable && vm.garminDisabledReason != nil, "import stays disabled offline")

        hub.readsFail = false
        hub.garminError = nil
        _ = await launchDrainer(outbox, hub: hub).drainOnce()
        #expect(hub.calls.filter { $0 == "PUSH 7" }.count == 2, "one failed in-tap attempt + one delivery")
        #expect(try outbox.pending().isEmpty)
        await vm.load()
        #expect(vm.pendingPushIds.isEmpty && vm.pushDisabledReason(for: vm.templates[0]) == nil)
    }

    @Test func b52p4_pushRejectedByTheHubIsRetiredWithItsWords() async throws {
        let db = try AppDatabase.inMemory()
        let outbox = Outbox(db: db)
        let row = WorkoutTemplate(templateId: 3, name: "Odd", activity: "running", location: .outdoor, weekdays: [], steps: [],
                                  updatedAt: "2026-10-05T08:00:00Z",
                                  segments: [WorkoutSegment(sport: .running, steps: [.cardio(CardioStep(purpose: .work, end: .time(seconds: 600), target: .none))])])
        let hub = FakeWorkoutHub(rows: [row])
        hub.garminError = HubError.http(status: 422, detail: "unsupported step")
        let vm = WorkoutLibraryViewModel(provider: hub, cache: nil, outbox: outbox)
        await vm.load()
        await vm.pushToGarmin(vm.templates[0])
        #expect(vm.notice == .init(text: "unsupported step", isError: true))
        #expect(try vm.pendingPushIds.isEmpty && outbox.pending().isEmpty)
    }
}
