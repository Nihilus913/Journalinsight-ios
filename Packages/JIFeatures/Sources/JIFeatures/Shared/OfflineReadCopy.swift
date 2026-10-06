import Foundation
import JICore
import JIHub

/// B-52 p3 (reads: rest): the one sentence a screen shows when the hub is unreachable AND there is
/// nothing cached for it yet (fresh install, never synced, or a route never read on this phone).
///
/// With a cached copy, every read already answers offline: `SectionLoader` sections fall back to
/// their own `OfflineCache` rows, and every other hub GET goes through `HubClient`'s read-through
/// cache (B-52 p1). So the only offline face left is the honest cold-cache one — never a fabricated
/// value, never the retired "Hub unreachable — …" Mac-asleep line that read like a failure of the
/// phone rather than "nothing saved here yet" (card B-52 open question 3, conservative default).
public nonisolated enum OfflineReadCopy {
    /// The title a cold-cache screen leads with (pinned by `B52OfflineReadsRestTests`).
    public static let coldCacheTitle = "No cached data yet"
    /// The full line every rest-of-app screen's error phase shows for an offline cold cache.
    public static let coldCache =
        "No cached data yet — the hub is unreachable and this screen hasn't loaded on this phone before. It fills in after the first sync with the hub."

    /// "The hub is not there" (no connection, timeout, a proxy 500/503/504) — the same test the hub
    /// client uses to decide a read may be answered from cache. Named hub answers (401, 409, 502,
    /// 404, 422 …) are never offline.
    public static func isOffline(_ error: Error) -> Bool { HubClient.isOfflineFailure(error) }

    /// The error-phase message for a load that has NOTHING to show: offline → `coldCache`, anything
    /// else → the screen's own named copy (`otherwise`).
    public static func emptyFailure(_ error: Error, otherwise: (Error) -> String) -> String {
        isOffline(error) ? coldCache : otherwise(error)
    }
}
