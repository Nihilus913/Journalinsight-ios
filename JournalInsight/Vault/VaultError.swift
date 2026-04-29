// JournalInsight/Vault/VaultError.swift
import Foundation

enum VaultError: Error, LocalizedError, Equatable {
    case userCancelled
    case osBlocked
    case keychainUnavailable
    case iCloudKeychainUnavailable
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Authentication was cancelled."
        case .osBlocked:
            return "Face ID or Touch ID is temporarily disabled. Unlock your iPhone to retry."
        case .keychainUnavailable:
            return "The Keychain is currently unavailable."
        case .iCloudKeychainUnavailable:
            return "iCloud Keychain isn’t available. Sign into iCloud and turn on Keychain to use encrypted journaling."
        case .decryptionFailed:
            return "Unable to decrypt this entry."
        }
    }
}
