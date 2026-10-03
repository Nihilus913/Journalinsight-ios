import Foundation
import Testing
@testable import JIWorkouts

/// W-B38-B B-3 — Watch ⇄ phone strength bridge over a fake transport (WatchConnectivity and the
/// mirrored `HKWorkoutSession` are device evidence).
@MainActor
struct StrengthSessionBridgeTests {
    private let t0 = Date(timeIntervalSince1970: 1_791_000_000)
    private let session = UUID()

    private func set(_ id: UUID = UUID(), index: Int = 1, kg: Double? = 60, reps: Int? = 8) -> StrengthBridgeSet {
        StrengthBridgeSet(clientId: id, sessionClientId: session, exerciseKey: "barbell_bench_press", exerciseId: 41,
                          setIndex: index, kind: .reps, reps: reps, weightKg: kg, durationS: nil, rpe: 8, performedAt: t0)
    }

    private var plan: StrengthWatchPlan {
        StrengthWatchPlan(date: "2026-10-05", planSessionId: 7, title: "Upper A", hrLimitBpm: 175, exercises: [
            StrengthWatchExercise(exerciseKey: "barbell_bench_press", exerciseId: 41, name: "Barbell Bench Press", kind: .reps,
                                  targetSets: 3, targetReps: 8, targetDurationS: nil, nextKg: 62.5, stepKg: 2.5, restS: 120,
                                  muscle: "Chest", lastSet: StrengthWatchLastSet(weightKg: 60, reps: 8, durationS: nil)),
            StrengthWatchExercise(exerciseKey: "plank", exerciseId: nil, name: "Plank", kind: .timed,
                                  targetSets: 2, targetReps: nil, targetDurationS: 45, nextKg: nil, stepKg: nil, restS: 60,
                                  muscle: "Core", lastSet: nil),
        ])
    }

    @Test func envelopeRoundTrips() throws {
        let events: [StrengthBridgeEvent] = [
            .sessionStarted(StrengthBridgeSessionStart(sessionClientId: session, planSessionId: 7, date: "2026-10-05", startedAt: t0)),
            .setLogged(set()), .setEdited(set(kg: 65)),
            .setDeleted(clientId: UUID(), sessionClientId: session),
            .heartRate(bpm: 141, at: t0),
            .sessionEnded(StrengthBridgeSessionEnd(sessionClientId: session, endedAt: t0, hkWorkoutUUID: UUID())),
        ]
        for e in events {
            let env = StrengthBridgeEnvelope(event: e)
            let back = try StrengthBridgeEnvelope.decode(env.encoded())
            #expect(back == env)
        }
    }

    @Test func planRoundTripsThroughApplicationContext() throws {
        let transport = FakeStrengthBridgeTransport()
        let phone = StrengthSessionPhoneBridge(transport: transport, sink: RecordingSink())
        try phone.sendPlan(plan)
        let watch = StrengthSessionWatchBridge(transport: transport)
        watch.receive(applicationContext: transport.applicationContext)
        #expect(watch.plan == plan)
    }

    @Test func watchSendsOverTheMirrorWhenMirrored() async {
        let transport = FakeStrengthBridgeTransport()
        transport.canSendToRemoteWorkoutSession = true
        let watch = StrengthSessionWatchBridge(transport: transport)
        await watch.send(.setLogged(set()))
        #expect(transport.remoteSends.count == 1)
        #expect(transport.userInfos.isEmpty)
    }

    @Test func watchFallsBackToTransferUserInfo() async {
        let transport = FakeStrengthBridgeTransport()
        let watch = StrengthSessionWatchBridge(transport: transport)
        await watch.send(.setLogged(set()))
        #expect(transport.remoteSends.isEmpty)
        #expect(transport.userInfos.count == 1)

        transport.canSendToRemoteWorkoutSession = true
        transport.remoteError = FakeStrengthBridgeTransport.Failure.notReachable
        await watch.send(.setLogged(set()))
        #expect(transport.userInfos.count == 2) // mirror failed → queued, never lost
    }

    @Test func heartRateIsNeverQueuedForLater() async {
        let transport = FakeStrengthBridgeTransport()
        let watch = StrengthSessionWatchBridge(transport: transport)
        await watch.send(.heartRate(bpm: 120, at: t0))
        #expect(transport.userInfos.isEmpty) // a stale HR reading is worse than none
    }

    @Test func phoneWritesEachEventIntoTheSink() async throws {
        let sink = RecordingSink()
        let phone = StrengthSessionPhoneBridge(transport: FakeStrengthBridgeTransport(), sink: sink)
        let s = set()
        let workout = UUID()
        for e: StrengthBridgeEvent in [
            .sessionStarted(StrengthBridgeSessionStart(sessionClientId: session, planSessionId: nil, date: "2026-10-05", startedAt: t0)),
            .setLogged(s), .setEdited(set(s.clientId, kg: 65)),
            .setDeleted(clientId: s.clientId, sessionClientId: session),
            .sessionEnded(StrengthBridgeSessionEnd(sessionClientId: session, endedAt: t0, hkWorkoutUUID: workout)),
        ] {
            await phone.receive(try StrengthBridgeEnvelope(event: e).encoded())
        }
        #expect(sink.log == ["start", "log \(s.clientId)", "edit 65.0", "delete \(s.clientId)", "end \(workout)"])
    }

    @Test func duplicateSetClientIdIsIgnored() async throws {
        let sink = RecordingSink()
        let phone = StrengthSessionPhoneBridge(transport: FakeStrengthBridgeTransport(), sink: sink)
        let s = set()
        // Same set over the mirror AND the userInfo fallback (two envelopes, one client_id).
        await phone.receive(try StrengthBridgeEnvelope(event: .setLogged(s)).encoded())
        await phone.receive(userInfo: ["strength": try StrengthBridgeEnvelope(event: .setLogged(s)).encoded()])
        // Same envelope replayed.
        let env = try StrengthBridgeEnvelope(event: .setEdited(set(s.clientId, kg: 70))).encoded()
        await phone.receive(env)
        await phone.receive(env)
        #expect(sink.log == ["log \(s.clientId)", "edit 70.0"])
    }

    @Test func garbageIsDropped() async {
        let sink = RecordingSink()
        let phone = StrengthSessionPhoneBridge(transport: FakeStrengthBridgeTransport(), sink: sink)
        await phone.receive(Data("nope".utf8))
        await phone.receive(userInfo: ["other": 1])
        #expect(sink.log.isEmpty)
    }

    @Test func heartRateReachesTheLiveListenerOnly() async throws {
        let sink = RecordingSink()
        let phone = StrengthSessionPhoneBridge(transport: FakeStrengthBridgeTransport(), sink: sink)
        var live: [StrengthBridgeEvent] = []
        phone.onEvent = { live.append($0) }
        await phone.receive(try StrengthBridgeEnvelope(event: .heartRate(bpm: 150, at: t0)).encoded())
        #expect(sink.log.isEmpty)
        #expect(live == [.heartRate(bpm: 150, at: t0)])
    }
}

@MainActor
private final class RecordingSink: StrengthSessionLogSink {
    var log: [String] = []
    func bridgeSessionStarted(_ start: StrengthBridgeSessionStart) async { log.append("start") }
    func bridgeSetLogged(_ set: StrengthBridgeSet) async { log.append("log \(set.clientId)") }
    func bridgeSetEdited(_ set: StrengthBridgeSet) async { log.append("edit \(set.weightKg ?? -1)") }
    func bridgeSetDeleted(clientId: UUID, sessionClientId: UUID) async { log.append("delete \(clientId)") }
    func bridgeSessionEnded(_ end: StrengthBridgeSessionEnd) async { log.append("end \(end.hkWorkoutUUID.map(\.uuidString) ?? "nil")") }
}
