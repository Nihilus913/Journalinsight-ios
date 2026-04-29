import Foundation

/// User-facing policy for how aggressively the in-memory master key
/// is purged from `VaultManager` after the app enters background.
///
/// `immediately` purges the key on every `scenePhase != .active`.
/// All other cases start a timer that fires after the named duration.
enum LockPolicy: String, CaseIterable, Codable, Sendable {
    case immediately
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case oneHour

    static let `default`: LockPolicy = .fiveMinutes

    var duration: Duration {
        switch self {
        case .immediately:    return .seconds(0)
        case .oneMinute:      return .seconds(60)
        case .fiveMinutes:    return .seconds(300)
        case .fifteenMinutes: return .seconds(900)
        case .oneHour:        return .seconds(3600)
        }
    }

    var displayLabel: String {
        switch self {
        case .immediately:    return "Immediately"
        case .oneMinute:      return "After 1 minute"
        case .fiveMinutes:    return "After 5 minutes"
        case .fifteenMinutes: return "After 15 minutes"
        case .oneHour:        return "After 1 hour"
        }
    }
}
