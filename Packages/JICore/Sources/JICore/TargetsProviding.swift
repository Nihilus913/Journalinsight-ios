import Foundation

/// W-TGT — the hub copy of the phone's `TargetsDocument` (spec §3; TEMP bridge until B-50). The
/// phone's PrefStore `targets.v1` is the source of truth; this is its mirror, one full body.
public protocol TargetsProviding: Sendable {
    /// `GET /api/v1/planning/targets`
    func targets() async throws -> TargetsDocument
    /// `PUT /api/v1/planning/targets` — replaces the hub's document; answers the stored one.
    func putTargets(_ document: TargetsDocument) async throws -> TargetsDocument
}
