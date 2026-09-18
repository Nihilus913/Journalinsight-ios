import Foundation
import UserNotifications
@testable import JIFeatures

/// In-memory `ReminderNotificationCenter` — records adds/removes so tests assert the exact
/// identifiers + triggers the scheduler hands the real centre.
@MainActor
final class FakeNotificationCenter: ReminderNotificationCenter {
    var pending: [UNNotificationRequest] = []
    var removed: [String] = []
    var status: UNAuthorizationStatus
    var grantOnRequest = true
    var throwOnRequest = false
    var throwOnAdd = false
    var authorizationRequests = 0

    struct Failure: Error {}

    init(status: UNAuthorizationStatus = .authorized) { self.status = status }

    func pendingRequests() async -> [UNNotificationRequest] { pending }

    func add(_ request: UNNotificationRequest) async throws {
        if throwOnAdd { throw Failure() }
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
    }

    func removePendingRequests(withIdentifiers ids: [String]) {
        removed.append(contentsOf: ids)
        pending.removeAll { ids.contains($0.identifier) }
    }

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        if throwOnRequest { throw Failure() }
        if grantOnRequest { status = .authorized }
        return grantOnRequest
    }
}
