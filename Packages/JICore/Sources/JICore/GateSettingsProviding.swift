import Foundation

/// B-57 W4 — the hub copy of the user's gate settings (preset, optional HR cap, zones), read by the
/// 05:10 `morning_go` run. The phone's `PrefStore` is the source of truth; this is its mirror.
public protocol GateSettingsProviding: Sendable {
    /// `GET /api/v1/planning/gate-settings`
    func gateSettings() async throws -> GateSettingsDTO
    // W-FIX10 F10-1: `putGateSettings` (`PUT /planning/gate-settings`, removed hub-side by W-TGT)
    // is gone — the settings reach the hub inside the targets document (`TargetsProviding`).
}
