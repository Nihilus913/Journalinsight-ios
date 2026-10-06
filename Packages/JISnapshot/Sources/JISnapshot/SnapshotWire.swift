import Foundation

/// W-B78 (B-78): the phone → watch WatchConnectivity wire for the `HubSnapshot`.
///
/// A watch has no access to the phone's App Group, so the snapshot travels in the WCSession
/// application context under `key` (latest-wins, queued until the Watch app wakes). The context is
/// shared with the strength plan — senders must MERGE (`StrengthBridgeTransport.mergeApplicationContext`),
/// never replace. Token-free by construction (`HubSnapshot` carries no secret).
public enum SnapshotWire {
    /// The application-context key. Must equal `StrengthBridgeKeys.snapshot` (JIWorkouts).
    public static let key = "ji.snapshot"
    /// The applicationContext budget is ~65 KB shared with the plan: above this the
    /// configurable-widget `allKpis` list is dropped (the glances never read it).
    public static let maxBytes = 30 * 1024

    public static func encode(_ snapshot: HubSnapshot) throws -> Data {
        let data = try JSONEncoder().encode(snapshot)
        guard data.count > maxBytes, snapshot.allKpis != nil else { return data }
        var trimmed = snapshot
        trimmed.allKpis = nil
        return try JSONEncoder().encode(trimmed)
    }

    /// nil for anything that is not a `HubSnapshot` (garbage never replaces a stored copy).
    public static func decode(_ data: Data) -> HubSnapshot? {
        try? JSONDecoder().decode(HubSnapshot.self, from: data)
    }

    /// The snapshot inside a received application context, if any.
    public static func snapshot(in context: [String: Any]) -> HubSnapshot? {
        (context[key] as? Data).flatMap(decode)
    }
}
