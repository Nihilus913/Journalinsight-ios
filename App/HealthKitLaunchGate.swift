import Foundation

/// W-BUG1 BUG1-6 (RG-77): the one place `-no-healthkit` (scripted simulator runs, B-46) is read.
/// Every HealthKit authorization request in the app goes through `requestIfAllowed`, so a run
/// with the flag can never put the system Health access sheet over the screen it scripts.
enum HealthKitLaunchGate {
    nonisolated static let flag = "-no-healthkit"

    nonisolated static func allowsHealthKit(arguments: [String] = CommandLine.arguments) -> Bool {
        !arguments.contains(flag)
    }

    /// Runs `request` only when HealthKit is allowed; returns whether it ran.
    @discardableResult
    static func requestIfAllowed(arguments: [String] = CommandLine.arguments,
                                 _ request: () async throws -> Void) async rethrows -> Bool {
        guard allowsHealthKit(arguments: arguments) else { return false }
        try await request()
        return true
    }
}
