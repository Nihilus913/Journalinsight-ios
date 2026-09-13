import Foundation
import Security

public protocol SecretStore: Sendable {
    func read(_ key: String) throws -> Data?
    func write(_ key: String, _ data: Data) throws
    func delete(_ key: String) throws
}

public struct KeychainError: Error, Equatable { public let status: OSStatus }

/// Device-only, available after first unlock (widgets/background refresh can read). Never synced.
public struct KeychainStore: SecretStore {
    public let service: String
    public init(service: String = "toby913.JournalInsight.hub") { self.service = service }

    private func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }
    public func read(_ key: String) throws -> Data? {
        var q = base(key); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &out)
        if s == errSecItemNotFound { return nil }
        guard s == errSecSuccess else { throw KeychainError(status: s) }
        return out as? Data
    }
    public func write(_ key: String, _ data: Data) throws {
        try delete(key)
        var q = base(key)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let s = SecItemAdd(q as CFDictionary, nil)
        guard s == errSecSuccess else { throw KeychainError(status: s) }
    }
    public func delete(_ key: String) throws {
        let s = SecItemDelete(base(key) as CFDictionary)
        guard s == errSecSuccess || s == errSecItemNotFound else { throw KeychainError(status: s) }
    }
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable { // @unchecked: lock-guarded dictionary
    private let lock = NSLock(); private var items: [String: Data] = [:]
    public init() {}
    public func read(_ key: String) throws -> Data? { lock.withLock { items[key] } }
    public func write(_ key: String, _ data: Data) throws { lock.withLock { items[key] = data } }
    public func delete(_ key: String) throws { lock.withLock { items[key] = nil } }
}
