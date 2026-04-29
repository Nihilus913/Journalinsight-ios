// JournalInsight/Vault/VaultManager.swift
import Foundation
import CryptoKit
import SwiftUI
import os

actor VaultManager {

    enum State: Equatable {
        case sealed
        case unlocking
        case unlocked(SymmetricKey)
        case osBlocked

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.sealed, .sealed),
                 (.unlocking, .unlocking),
                 (.unlocked, .unlocked),                 // ignore key payload
                 (.osBlocked, .osBlocked):
                return true
            default:
                return false
            }
        }
    }

    private let keychain: KeychainService
    private let lockPolicy: LockPolicySettings
    private var state: State = .sealed
    private var idleTask: Task<Void, Never>?
    private var lastBackgroundEntry: Date?

    init(keychain: KeychainService, lockPolicy: LockPolicySettings) {
        self.keychain = keychain
        self.lockPolicy = lockPolicy
    }

    var currentState: State { state }
    var isUnlocked: Bool {
        if case .unlocked = state { return true }
        return false
    }

    /// Returns a session-cached master key, prompting biometric and loading
    /// (or generating) the iCloud-Keychain key on first call.
    func sessionKey() async throws -> SymmetricKey {
        if case .unlocked(let key) = state { return key }
        if case .osBlocked = state { throw VaultError.osBlocked }
        state = .unlocking
        do {
            let key = try await keychain.loadMasterKey()
            state = .unlocked(key)
            return key
        } catch KeychainError.itemNotFound {
            do {
                let key = try await keychain.storeNewMasterKey()
                state = .unlocked(key)
                return key
            } catch let error as KeychainError {
                state = mapErrorToState(error)
                throw map(error)
            } catch {
                state = .sealed
                throw VaultError.keychainUnavailable
            }
        } catch let error as KeychainError {
            state = mapErrorToState(error)
            throw map(error)
        } catch {
            Logger.vault.error("loadMasterKey unexpected: \(error.localizedDescription, privacy: .public)")
            state = .sealed
            throw VaultError.keychainUnavailable
        }
    }

    func lockNow() {
        idleTask?.cancel()
        idleTask = nil
        lastBackgroundEntry = nil
        state = .sealed
    }

    // MARK: - Error mapping

    private func mapErrorToState(_ error: KeychainError) -> State {
        switch error {
        case .biometryLockout: return .osBlocked
        default:               return .sealed
        }
    }

    private func map(_ error: KeychainError) -> VaultError {
        switch error {
        case .userCancelled, .authFailed: return .userCancelled
        case .biometryLockout:            return .osBlocked
        case .interactionNotAllowed:      return .iCloudKeychainUnavailable
        case .itemNotFound:               return .keychainUnavailable    // unreachable here
        case .unexpectedStatus:           return .keychainUnavailable
        }
    }
}
