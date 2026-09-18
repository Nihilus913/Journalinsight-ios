import Foundation

/// W7-L2 (P-apns-push) — this feature's own protocol, added fresh rather than growing the frozen
/// `HealthDataProvider` (same Data-seam convention as `WeighInProviding`/`TrainingProviding`:
/// `HealthDataProvider`/`HubDataProvider`/`MockDataProvider` are frozen; each lane adds its own
/// protocol in a new file and conforms the providers in `+Push` extension files).
///
/// Deliberately NOT part of `DataCapability`: registering a device token is a property of the
/// *hub transport*, not of a data source. A T2/HealthKit provider (W7-L3) simply doesn't conform,
/// so `ApnsRegistration` finds no registrar and stays in its "no hub to register with" state
/// rather than reporting a false success (CLAUDE.md rule 5).
public protocol PushTokenProviding: Sendable {
    /// `POST /api/v1/planning/push-token` (W7-L1, `app/planning/router.py`) — upserts this device's
    /// APNs token so the hub's `ApnsSink` can reach it at 05:10. Called on every cold launch:
    /// APNs may hand back a rotated token at any time, and the hub upserts on `token`, so
    /// re-registering an unchanged token is a cheap no-op rather than a duplicate row.
    ///
    /// Errors are the usual named `HubError`s (`.unauthorized` when `HT_API_TOKEN` is wrong,
    /// `.network` when the hub is asleep). A failure here must never be fatal — ntfy remains the
    /// primary channel (spec L27 "ntfy first"); APNs is additive.
    func registerPushToken(_ registration: PushTokenRegistration) async throws -> PushTokenAck
}
