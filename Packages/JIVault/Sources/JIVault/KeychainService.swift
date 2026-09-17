import Foundation
import Security
import CryptoKit

public enum KeychainError: Error, Equatable, Sendable {
    case itemNotFound
    case unexpectedStatus(OSStatus)
}

/// Abstracts Keychain access behind a protocol so `VaultManager` can be
/// tested against an in-memory fake. Adapted from XC donor commit 4b012de
/// (`JournalInsight/Vault/KeychainService.swift`) but with the stricter
/// attributes W4 requires: device-only, never synced (JIVault's master key
/// protects the whole local vault; unlike the donor's per-entry
/// iCloud-Keychain design, W4 keeps it un-synchronized — see JIHub
/// `KeychainStore.swift` for the same device-only idiom this borrows, though
/// JIVault owns its own service rather than reusing that store).
public protocol KeychainService: Sendable {
    /// Loads the master key. Throws `.itemNotFound` if none exists yet.
    func loadMasterKey() async throws -> SymmetricKey

    /// Generates a fresh 256-bit master key and stores it. Only call after
    /// `loadMasterKey()` threw `.itemNotFound`.
    func storeNewMasterKey() async throws -> SymmetricKey

    /// Removes the master key from this device's Keychain.
    func deleteMasterKey() async throws
}

/// Production implementation. `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
/// keeps the item device-only (no iCloud Keychain sync) — no separate
/// "make it synchronizable" attribute is set anywhere in this package.
public struct SecureKeychainService: KeychainService {
    static let service = "toby913.JournalInsight.vault"
    static let account = "vault.master"

    public init() {}

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    public func loadMasterKey() async throws -> SymmetricKey {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeychainError.unexpectedStatus(status) }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func storeNewMasterKey() async throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }

        // Defensive: clear any pre-existing item before adding.
        SecItemDelete(baseQuery() as CFDictionary)

        var attributes = baseQuery()
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        attributes[kSecValueData as String] = keyData

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        return key
    }

    public func deleteMasterKey() async throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
