import JISnapshot
import JIWorkouts

// W-B78 B78-2: the ONE WCSession transport (and its Fake) is the pusher's context sink —
// `mergeApplicationContext(key:value:)` is the merge-safe write from B78-1.
extension WatchConnectivityStrengthTransport: SnapshotContextSink {}
extension FakeStrengthBridgeTransport: SnapshotContextSink {}
