// JournalInsight/Vault/LockPolicySettings.swift
import Foundation
import Observation

/// `@Observable` wrapper that persists `LockPolicy` to UserDefaults.
/// Injectable suite for tests.
@Observable
final class LockPolicySettings {
    @ObservationIgnored
    private let suite: UserDefaults

    init(suite: UserDefaults = .standard) {
        self.suite = suite
    }

    var current: LockPolicy {
        get {
            access(keyPath: \.current)
            let raw = suite.string(forKey: StorageKeys.lockPolicy)
            return raw.flatMap(LockPolicy.init(rawValue:)) ?? .fiveMinutes
        }
        set {
            withMutation(keyPath: \.current) {
                suite.set(newValue.rawValue, forKey: StorageKeys.lockPolicy)
            }
        }
    }
}
