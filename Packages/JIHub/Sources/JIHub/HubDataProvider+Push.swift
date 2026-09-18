import Foundation
import JICore

/// W7-L2 (P-apns-push). Uses `HubDataProvider.client` directly (widened to internal by W3b-L0,
/// B-14) — no `Mirror`, no second `HubClient` construction, same shape as `HubDataProvider+WeighIn`.
///
/// The path and body are the W7 card's push contract verbatim; `HubClient.post` supplies the
/// `Authorization: Bearer <HT_API_TOKEN>` header every `/api/v1/*` route requires and maps a 401
/// to `HubError.unauthorized`.
extension HubDataProvider: PushTokenProviding {
    public func registerPushToken(_ registration: PushTokenRegistration) async throws -> PushTokenAck {
        try await client.post("/api/v1/planning/push-token", body: registration)
    }
}
