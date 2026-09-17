import Foundation
import Observation

/// `@Observable` wrapper persisting `LockPolicy` to UserDefaults. Adapted
/// from XC donor commit 4b012de
/// (`JournalInsight/Vault/LockPolicySettings.swift`); injectable suite for
/// tests.
@Observable
public final class LockPolicySettings {
    @ObservationIgnored
    private let suite: UserDefaults
    @ObservationIgnored
    private let storageKey: String

    public init(suite: UserDefaults = .standard, storageKey: String = "com.tobias.JournalInsight.vault.lockPolicy") {
        self.suite = suite
        self.storageKey = storageKey
    }

    public var current: LockPolicy {
        get {
            access(keyPath: \.current)
            let raw = suite.string(forKey: storageKey)
            return raw.flatMap(LockPolicy.init(rawValue:)) ?? .default
        }
        set {
            withMutation(keyPath: \.current) {
                suite.set(newValue.rawValue, forKey: storageKey)
            }
        }
    }
}
