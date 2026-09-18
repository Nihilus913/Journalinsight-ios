import Foundation

/// The one place "how old is too old?" is decided (W7-L4, P-hub-watchdog).
///
/// Port of the RN oracle's global `staleTime` floor — `mobile/src/data/queryKeys.ts:71–77`
/// (`HUB_QUERY_STALE_TIME_MS = 45_000`, "mid-band of the story's 30–60s target"). The oracle kept
/// the number in `queryKeys.ts` rather than inline in the `QueryClient` so any code reasoning about
/// "can I skip a refetch?" imports the same constant the client actually uses; the same reasoning
/// applies here, which is why `SectionLoader` and `HubWatchdog` both read it from here instead of
/// hand-copying 45.
///
/// Deliberately has NO access to a clock: every entry point takes `now` explicitly (no `Date()`,
/// no `Calendar.current`, no `TimeZone.current`), so staleness is testable at exact boundaries and
/// a view model's injected clock is honoured end to end.
nonisolated public enum Staleness {
    /// Seconds after which a hub-backed value counts as stale. Also the `HubWatchdog` probe period
    /// — a screen can never be showing data older than the staleness floor without the watchdog
    /// having had a chance to say whether the hub is still there.
    public static let hubQueryStaleTime: TimeInterval = 45

    /// `true` when `fetchedAt` is at least `staleTime` seconds behind `now`.
    ///
    /// A `nil` `fetchedAt` is stale: "never fetched" is not "fresh" (CLAUDE.md rule 5 — never
    /// render a zero, and never imply freshness we cannot back). The boundary is inclusive
    /// (exactly `staleTime` old IS stale) so the floor is a maximum age, not a strict one.
    /// A `fetchedAt` in the future (clock skew) yields a negative age and is treated as fresh.
    public static func isStale(
        fetchedAt: Date?,
        now: Date,
        staleTime: TimeInterval = Staleness.hubQueryStaleTime
    ) -> Bool {
        guard let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) >= staleTime
    }
}
