import JICore
import JICompute
import JIDesign

/// W-OFFLINE OFF-2 (B-50 slice 1): tile id → the `ParityRegistry` key it displays. The keys are the
/// registry's `.hubOnly` ones — Garmin's own readings that JI never recomputes or approximates on
/// device (decision #23). `readiness` is the hub's readiness numeral (`readiness_hub_input_2_2`):
/// fetched from the hub, never recomputed locally.
public nonisolated let hubOnlyTileRegistryKeys: [String: String] = [
    "hrv": "hrv",
    "body_battery": "body_battery",
    "bodyBattery": "body_battery",   // Recovery's "Also watching" tile id
    "readiness": "readiness_hub_input_2_2",
]

/// True when the active source is the hub (the full T1 capability set), the same test as
/// `RecoveryViewModel.isOnDeviceSource`.
public nonisolated func providerIsHub(_ capabilities: DataCapability) -> Bool { capabilities.isSuperset(of: .hubAll) }

/// True when tile `id` shows a `.hubOnly` metric and the active source is not the hub: the tile
/// says `JIMissingReason.needsHub` instead of "—", a zero, or a cached hub value.
public nonisolated func hubOnlyTileNeedsHub(_ id: String, capabilities: DataCapability) -> Bool {
    guard !providerIsHub(capabilities), let key = hubOnlyTileRegistryKeys[id] else { return false }
    return ParityRegistry.source(for: key) == .hubOnly
}
