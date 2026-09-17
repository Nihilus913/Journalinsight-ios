import Foundation

/// W3b-L1 (P-session-coach) — optional-capability protocol, deliberately kept SEPARATE from
/// `DataCapability` rather than folding a new flag into it: every existing `DataCapability` bit
/// is a domain both current providers (`MockDataProvider`, `HubDataProvider`) fully implement, but
/// no real hub endpoint streams live in-session heart rate — this pipeline syncs Garmin/YAZIO
/// after the fact (CLAUDE.md), it doesn't watch a workout live. `HubDataProvider` deliberately does
/// NOT conform (mirrors `mobile/src/data/HubDataProvider.ts` L138's own `sessionCapabilities =
/// undefined` — no BLE strap / Garmin / HealthKit live-workout stream exists server-side yet).
///
/// A screen tests capability with `provider as? any LiveSessionProviding` and renders the RN
/// oracle's "not available" wall whenever that cast is `nil` — never a fake or zeroed reading
/// standing in for a real one (CLAUDE.md rule 5). `MockDataProvider` is the only conformer today
/// (`MockDataProvider+LiveSession.swift`), exercising the live branch in previews/tests exactly
/// like the RN mock's synthesized dev feed does.
public protocol LiveSessionProviding: Sendable {
    /// One tick of the live in-session feed. Oracle: `DataProvider.getLiveSession()`
    /// (`mobile/src/data/useLiveSession.ts` polls this on `LIVE_SESSION_POLL_MS`, 2000 ms).
    func liveSession() async throws -> LiveSessionSample
}

/// Oracle: `LiveSessionSample` (`mobile/src/data/types.ts` L463-470).
public struct LiveSessionSample: Sendable, Equatable {
    /// `nil` when the live source hasn't produced a reading yet this tick — never a synthesized 0.
    public let hrBpm: Int?
    public let elapsedS: Int
    /// Whoop-Strain-Coach-style climbing session load, same units as `targetLoad`.
    public let load: Double
    public let targetLoad: Double

    public init(hrBpm: Int?, elapsedS: Int, load: Double, targetLoad: Double) {
        self.hrBpm = hrBpm
        self.elapsedS = elapsedS
        self.load = load
        self.targetLoad = targetLoad
    }
}
