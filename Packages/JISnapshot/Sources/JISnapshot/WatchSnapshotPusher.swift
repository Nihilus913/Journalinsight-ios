import Foundation

/// W-B78 B78-2: the one application-context writer the pusher needs. `StrengthBridgeTransport`
/// (JIWorkouts) already has this exact method; the App declares the conformance of the real
/// WatchConnectivity transport (and the Fake) so this package stays free of JIWorkouts.
@MainActor
public protocol SnapshotContextSink: AnyObject {
    func mergeApplicationContext(key: String, value: Data) throws
}

/// W-B78 (B-78) B78-2: the phone → Watch push of the glance `HubSnapshot`.
///
/// A watch cannot read the phone's App Group, so after `AppEnvironment.publishSnapshot` writes the
/// App-Group store it hands the same snapshot here, which merges it into the WCSession application
/// context under `SnapshotWire.key` via the ONE shared transport (owned by
/// `StrengthMirrorCoordinator` — never a second `WCSession`). The merge keeps the strength plan key.
///
/// · pushes only when the payload changed — `fetchedAt` alone is not a change (every republish
///   stamps a new one, and no glance shows it); the wire copy still carries the latest `fetchedAt`;
/// · no-op while the Watch app is not installed (the latest snapshot is kept);
/// · `sessionDidChange()` (activation / `sessionWatchStateDidChange`) re-pushes the latest one, and
///   a transport attached after a snapshot arrived sends it at once.
@MainActor
public final class WatchSnapshotPusher {
    public var transport: (any SnapshotContextSink)? {
        didSet { if transport != nil { sessionDidChange() } }
    }
    /// Pushes actually handed to the transport (test observability).
    public private(set) var pushCount = 0

    private let isWatchAppInstalled: () -> Bool
    private var latest: HubSnapshot?
    private var lastPushed: HubSnapshot?

    public init(isWatchAppInstalled: @escaping () -> Bool) {
        self.isWatchAppInstalled = isWatchAppInstalled
    }

    /// Called after every App-Group snapshot write.
    public func push(_ snapshot: HubSnapshot) {
        latest = snapshot
        if let lastPushed, Self.sameContent(lastPushed, snapshot) { return }
        send()
    }

    /// Session activated or the Watch pairing / install state changed: re-send the latest snapshot.
    public func sessionDidChange() {
        send()
    }

    private func send() {
        guard let latest, let transport, isWatchAppInstalled(),
              let data = try? SnapshotWire.encode(latest) else { return }
        do {
            try transport.mergeApplicationContext(key: SnapshotWire.key, value: data)
            lastPushed = latest
            pushCount += 1
        } catch {
            // Not activated yet / not paired: the activation callback re-sends.
        }
    }

    public static func sameContent(_ a: HubSnapshot, _ b: HubSnapshot) -> Bool {
        var a = a
        a.fetchedAt = b.fetchedAt
        return a == b
    }
}
