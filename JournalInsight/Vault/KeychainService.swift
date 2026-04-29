// JournalInsight/Vault/KeychainService.swift
import Foundation
import Security
import CryptoKit
import os

enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case userCancelled                  // errSecUserCanceled (-128)
    case interactionNotAllowed          // errSecInteractionNotAllowed (e.g. background)
    case authFailed                     // errSecAuthFailed
    case biometryLockout                // errSecBiometryLockout
}

/// Abstract Keychain operations behind a protocol so VaultManager can be
/// tested against an in-memory fake without touching the real Keychain.
protocol KeychainService: Sendable {
    /// Loads the master key. May trigger a biometric prompt.
    /// Throws `.itemNotFound` if no master key exists; caller should generate one.
    func loadMasterKey() async throws -> SymmetricKey

    /// Generates a fresh 256-bit master key, stores it as a synchronisable
    /// Keychain item with `.biometryCurrentSet` ACL, and returns it.
    /// Should only be called when `loadMasterKey()` returned `.itemNotFound`.
    func storeNewMasterKey() async throws -> SymmetricKey

    /// Removes the master key from this device's Keychain. iCloud Keychain
    /// will propagate the removal to other devices.
    func deleteMasterKey() async throws
}

/// Production implementation backed by Security framework.
/// Uses kSecAttrSynchronizable=true so the key is replicated via iCloud Keychain.
struct KeychainStore: KeychainService {
    static let service: String = "com.tobias.JournalInsight"
    static let account: String = "vault.master"

    func loadMasterKey() async throws -> SymmetricKey {
        var query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        Self.service,
            kSecAttrAccount as String:        Self.account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String:         true,
            kSecMatchLimit as String:         kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeychainError.unexpectedStatus(status) }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        case errSecUserCanceled:
            throw KeychainError.userCancelled
        case errSecInteractionNotAllowed:
            throw KeychainError.interactionNotAllowed
        case errSecAuthFailed:
            throw KeychainError.authFailed
        default:
            // -25293 is biometryLockout on some OS versions
            if status == -25293 { throw KeychainError.biometryLockout }
            Logger.vault.error("loadMasterKey unexpected status=\(status)")
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func storeNewMasterKey() async throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }

        var error: Unmanaged<CFError>?
        guard let acl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlocked,
            .biometryCurrentSet,
            &error
        ) else {
            if let err = error?.takeRetainedValue() {
                Logger.vault.error("acl create failed: \(err.localizedDescription, privacy: .public)")
            }
            throw KeychainError.unexpectedStatus(-1)
        }

        let attributes: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        Self.service,
            kSecAttrAccount as String:        Self.account,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessControl as String:  acl,
            kSecValueData as String:          keyData,
            kSecUseDataProtectionKeychain as String: true
        ]

        // Remove any pre-existing item before adding (defensive).
        let deleteQuery: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        Self.service,
            kSecAttrAccount as String:        Self.account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            Logger.vault.error("SecItemAdd failed status=\(addStatus)")
            throw KeychainError.unexpectedStatus(addStatus)
        }
        return key
    }

    func deleteMasterKey() async throws {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        Self.service,
            kSecAttrAccount as String:        Self.account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
