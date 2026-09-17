import Foundation
import CryptoKit

/// Vault lock state. Unlike XC donor commit 4b012de's `VaultManager.State`
/// (which carried a raw `SymmetricKey`), `.unlocked` carries a ready-to-use
/// `FieldCipher` — the shape L1–L3 stores actually consume — so callers
/// never touch key material directly.
public enum VaultStatus: Sendable {
    case locked
    case unlocked(any FieldCipher)
}

extension VaultStatus: Equatable {
    /// Ignores the `.unlocked` payload (an existential `FieldCipher` isn't
    /// itself Equatable), matching donor `VaultManager.State`'s own
    /// payload-blind `==`.
    public static func == (lhs: VaultStatus, rhs: VaultStatus) -> Bool {
        switch (lhs, rhs) {
        case (.locked, .locked), (.unlocked, .unlocked):
            return true
        default:
            return false
        }
    }
}

/// Owns the vault master key's lifecycle: unlock (load-or-generate from
/// Keychain), lock (drop the in-memory key), purge (delete the Keychain
/// item entirely — used by "reset vault" / failed-restore rollback paths).
/// Adapted from XC donor commit 4b012de (`JournalInsight/Vault/VaultManager.swift`);
/// simplified for W4 — idle-timer/scenePhase auto-lock is a JIFeatures-side
/// concern (not owned here), so this actor only exposes the state machine.
public actor VaultManager {
    private let keychain: KeychainService
    private var _status: VaultStatus = .locked

    public init(keychain: KeychainService) {
        self.keychain = keychain
    }

    public var status: VaultStatus { _status }

    /// Returns the current session cipher, unlocking (loading or, on first
    /// run, generating the master key) if necessary.
    @discardableResult
    public func unlock() async throws -> any FieldCipher {
        if case .unlocked(let cipher) = _status { return cipher }
        let key: SymmetricKey
        do {
            key = try await keychain.loadMasterKey()
        } catch KeychainError.itemNotFound {
            do {
                key = try await keychain.storeNewMasterKey()
            } catch {
                throw VaultError.keychainUnavailable
            }
        } catch {
            throw VaultError.keychainUnavailable
        }
        let cipher = EnvelopeFieldCipher(key: key)
        _status = .unlocked(cipher)
        return cipher
    }

    /// Drops the in-memory session cipher. The Keychain item is untouched —
    /// the next `unlock()` reloads the same key.
    public func lock() {
        _status = .locked
    }

    /// Deletes the master key from the Keychain and locks. Irreversible —
    /// every envelope this key ever sealed becomes permanently
    /// undecryptable. Used by "reset vault" and by a failed Fold-archive
    /// restore's rollback.
    public func purge() async throws {
        do {
            try await keychain.deleteMasterKey()
        } catch {
            throw VaultError.keychainUnavailable
        }
        _status = .locked
    }
}
