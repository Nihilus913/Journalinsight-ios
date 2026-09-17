import Foundation

/// User/UI-facing vault errors. Adapted from XC donor commit 4b012de
/// (`JournalInsight/Vault/VaultError.swift`) — trimmed to the cases this
/// package's `VaultManager`/`KeychainService` surface can actually produce.
public enum VaultError: Error, LocalizedError, Equatable, Sendable {
    case keychainUnavailable
    case decryptionFailed
    case wrongPassphrase

    public var errorDescription: String? {
        switch self {
        case .keychainUnavailable:
            return "The Keychain is currently unavailable."
        case .decryptionFailed:
            return "Unable to decrypt this entry."
        case .wrongPassphrase:
            return "That passphrase doesn't match this backup's vault key."
        }
    }
}
