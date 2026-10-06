import Foundation
import Testing
@testable import JISnapshot

/// W-B78 B78-2: `WatchSnapshotPusher` against a merging context sink (the same merge contract as
/// `FakeStrengthBridgeTransport.mergeApplicationContext`, JIWorkouts B78-1).
@MainActor
private final class MergingSink: SnapshotContextSink {
    private(set) var applicationContext: [String: Any] = [:]
    func mergeApplicationContext(key: String, value: Data) throws { applicationContext[key] = value }
}

@Suite @MainActor
struct WatchSnapshotPusherTests {
    private func snapshot(word: String = "GO", fetchedAt: Date = Date(timeIntervalSince1970: 1_789_128_000)) -> HubSnapshot {
        HubSnapshot(verdictWord: word, verdictSession: "Easy run", verdictTone: "go", verdictDate: "2026-09-11", readiness: 78,
                    kpis: [SnapshotKPI(label: "HRV", value: 52, unit: "ms")],
                    fetchedAt: fetchedAt, lastSync: Date(timeIntervalSince1970: 1_789_128_000))
    }

    private func pushed(_ sink: MergingSink) -> HubSnapshot? {
        SnapshotWire.snapshot(in: sink.applicationContext)
    }

    @Test func noPushWhenPayloadEqual() throws {
        let fake = MergingSink()
        let pusher = WatchSnapshotPusher(isWatchAppInstalled: { true })
        pusher.transport = fake
        pusher.push(snapshot())
        #expect(pusher.pushCount == 1)
        pusher.push(snapshot())
        #expect(pusher.pushCount == 1)
        // A new fetchedAt alone is not a change the glances can show — no re-push.
        pusher.push(snapshot(fetchedAt: Date(timeIntervalSince1970: 1_789_128_600)))
        #expect(pusher.pushCount == 1)
        pusher.push(snapshot(word: "EASY"))
        #expect(pusher.pushCount == 2)
        #expect(pushed(fake)?.verdictWord == "EASY")
    }

    @Test func planKeyRetained() throws {
        let fake = MergingSink()
        let planBytes = Data("plan".utf8)
        try fake.mergeApplicationContext(key: "strengthPlan", value: planBytes)
        let pusher = WatchSnapshotPusher(isWatchAppInstalled: { true })
        pusher.transport = fake
        pusher.push(snapshot())
        #expect(fake.applicationContext["strengthPlan"] as? Data == planBytes)
        #expect(pushed(fake)?.verdictWord == "GO")
    }

    @Test func noOpWhenWatchNotInstalledThenRepushOnInstall() throws {
        let fake = MergingSink()
        var installed = false
        let pusher = WatchSnapshotPusher(isWatchAppInstalled: { installed })
        pusher.transport = fake
        pusher.push(snapshot())
        #expect(pusher.pushCount == 0)
        #expect(fake.applicationContext.isEmpty)
        // Activation / `sessionWatchStateDidChange` with the Watch app now installed → latest goes out.
        installed = true
        pusher.sessionDidChange()
        #expect(pusher.pushCount == 1)
        #expect(pushed(fake)?.verdictWord == "GO")
    }

    @Test func repushOnActivationEvenWhenEqual() throws {
        let fake = MergingSink()
        let pusher = WatchSnapshotPusher(isWatchAppInstalled: { true })
        pusher.transport = fake
        pusher.push(snapshot())
        pusher.sessionDidChange()
        #expect(pusher.pushCount == 2)
    }

    @Test func snapshotBeforeTransportIsSentWhenTransportArrives() throws {
        let pusher = WatchSnapshotPusher(isWatchAppInstalled: { true })
        pusher.push(snapshot())   // no transport yet (coordinator installs it later at launch)
        #expect(pusher.pushCount == 0)
        let fake = MergingSink()
        pusher.transport = fake
        #expect(pusher.pushCount == 1)
        #expect(pushed(fake)?.verdictWord == "GO")
    }
}
