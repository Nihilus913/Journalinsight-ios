import Foundation

/// User-facing policy for how aggressively `VaultManager` locks itself
/// after the app backgrounds. Adapted verbatim (case set + durations) from
/// XC donor commit 4b012de (`JournalInsight/Vault/LockPolicy.swift`).
public enum LockPolicy: String, CaseIterable, Codable, Sendable {
    case immediately
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case oneHour

    public static let `default`: LockPolicy = .fiveMinutes

    public var duration: Duration {
        switch self {
        case .immediately: return .seconds(0)
        case .oneMinute: return .seconds(60)
        case .fiveMinutes: return .seconds(300)
        case .fifteenMinutes: return .seconds(900)
        case .oneHour: return .seconds(3600)
        }
    }

    public var displayLabel: String {
        switch self {
        case .immediately: return "Immediately"
        case .oneMinute: return "After 1 minute"
        case .fiveMinutes: return "After 5 minutes"
        case .fifteenMinutes: return "After 15 minutes"
        case .oneHour: return "After 1 hour"
        }
    }
}
