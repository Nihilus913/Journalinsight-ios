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

    // MARK: - Idle-timer / scenePhase

    func handleScenePhaseChange(_ phase: ScenePhase) async {
        switch phase {
        case .background, .inactive:
            handleEnteredBackground()
        case .active:
            handleBecameActive()
        @unknown default:
            break
        }
    }

    private func handleEnteredBackground() {
        guard isUnlocked else { return }
        let policy = lockPolicy.current
        if policy == .immediately {
            lockNow()
            return
        }
        lastBackgroundEntry = Date()
        idleTask?.cancel()
        let duration = policy.duration
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self else { return }
            await self.lockIfStillBackgrounded()
        }
    }

    private func handleBecameActive() {
        idleTask?.cancel()
        idleTask = nil
        guard isUnlocked, let last = lastBackgroundEntry else {
            lastBackgroundEntry = nil
            return
        }
        let elapsed = Date().timeIntervalSince(last)
        if elapsed >= TimeInterval(lockPolicy.current.duration.components.seconds) {
            lockNow()
        }
        lastBackgroundEntry = nil
    }

    private func lockIfStillBackgrounded() {
        // Called from the sleep task on the actor's executor.
        guard lastBackgroundEntry != nil else { return }
        lockNow()
    }

    /// Test-only helper — bumps `lastBackgroundEntry` backwards in time so
    /// the deadline comparison in `handleBecameActive` triggers without a real wait.
    /// Hidden under `#if DEBUG` to avoid shipping in release.
    #if DEBUG
    func simulateBackgroundElapsed(seconds: TimeInterval) {
        guard let last = lastBackgroundEntry else { return }
        lastBackgroundEntry = last.addingTimeInterval(-seconds)
    }
    #endif
}
