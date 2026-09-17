import Foundation
import JICore

/// W3b-L4 (P-weigh-in). Uses `HubDataProvider.client` directly (widened to internal by L0, B-14) —
/// no `Mirror`, no second `HubClient` construction.
extension HubDataProvider: WeighInProviding {
    public func logWeighin(weightKg: Double, date: String?) async throws -> WeighinResult {
        try await client.post("/api/v1/vitals/weighin", body: WeighinBody(weightKg: weightKg, date: date))
    }
}
