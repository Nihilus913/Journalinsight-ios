import Foundation

/// B-57 W4 — the hub copy of the user's gate settings (preset, optional HR cap, zones), read by the
/// 05:10 `morning_go` run. The phone's `PrefStore` is the source of truth; this is its mirror.
public protocol GateSettingsProviding: Sendable {
    /// `GET /api/v1/planning/gate-settings`
    func gateSettings() async throws -> GateSettingsDTO
    /// `PUT /api/v1/planning/gate-settings`
    func putGateSettings(_ body: GateSettingsBody) async throws -> GateSettingsDTO
}
