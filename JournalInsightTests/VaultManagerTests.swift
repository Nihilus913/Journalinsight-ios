// JournalInsightTests/VaultManagerTests.swift
import Testing
import Foundation
import CryptoKit
@testable import JournalInsight

@Suite("VaultManager")
struct VaultManagerTests {

    @Test("sessionKey loads existing key from keychain")
    func sessionKeyLoadsExisting() async throws {
        let fake = FakeKeychain()
        let known = SymmetricKey(size: .bits256)
        fake.seedKey(known)
        let settings = LockPolicySettings(suite: UserDefaults(suiteName: "test.vm.\(UUID())")!)
        let vault = VaultManager(keychain: fake, lockPolicy: settings)
        let key = try await vault.sessionKey()
        #expect(key == known)
        #expect(fake.loadCallCount == 1)
        #expect(fake.storeCallCount == 0)
    }

    @Test("sessionKey generates new key on errSecItemNotFound")
    func sessionKeyGeneratesNew() async throws {
        let fake = FakeKeychain()
        // No seeded key — load throws .itemNotFound, manager should generate.
        let settings = LockPolicySettings(suite: UserDefaults(suiteName: "test.vm.\(UUID())")!)
        let vault = VaultManager(keychain: fake, lockPolicy: settings)
        _ = try await vault.sessionKey()
        #expect(fake.loadCallCount == 1)
        #expect(fake.storeCallCount == 1)
    }

    @Test("sessionKey caches across calls")
    func sessionKeyCaches() async throws {
        let fake = FakeKeychain()
        fake.seedKey(SymmetricKey(size: .bits256))
        let settings = LockPolicySettings(suite: UserDefaults(suiteName: "test.vm.\(UUID())")!)
        let vault = VaultManager(keychain: fake, lockPolicy: settings)
        _ = try await vault.sessionKey()
        _ = try await vault.sessionKey()
        _ = try await vault.sessionKey()
        #expect(fake.loadCallCount == 1)        // only first call hits keychain
    }

    @Test("user-cancelled biometric throws VaultError.userCancelled")
    func userCancelled() async throws {
        let fake = FakeKeychain()
        fake.loadError = .userCancelled
        let settings = LockPolicySettings(suite: UserDefaults(suiteName: "test.vm.\(UUID())")!)
        let vault = VaultManager(keychain: fake, lockPolicy: settings)
        await #expect(throws: VaultError.userCancelled) {
            _ = try await vault.sessionKey()
        }
    }

    @Test("biometryLockout maps to osBlocked and persists state")
    func osBlocked() async throws {
        let fake = FakeKeychain()
        fake.loadError = .biometryLockout
        let settings = LockPolicySettings(suite: UserDefaults(suiteName: "test.vm.\(UUID())")!)
        let vault = VaultManager(keychain: fake, lockPolicy: settings)
        await #expect(throws: VaultError.osBlocked) {
            _ = try await vault.sessionKey()
        }
        let state = await vault.currentState
        #expect(state == .osBlocked)
    }

    @Test("lockNow purges cached key and forces re-load on next call")
    func lockNowPurges() async throws {
        let fake = FakeKeychain()
        fake.seedKey(SymmetricKey(size: .bits256))
        let settings = LockPolicySettings(suite: UserDefaults(suiteName: "test.vm.\(UUID())")!)
        let vault = VaultManager(keychain: fake, lockPolicy: settings)
        _ = try await vault.sessionKey()
        await vault.lockNow()
        let stateAfter = await vault.currentState
        #expect(stateAfter == .sealed)
        _ = try await vault.sessionKey()
        #expect(fake.loadCallCount == 2)
    }

    @Test("isUnlocked reflects state")
    func isUnlocked() async throws {
        let fake = FakeKeychain()
        fake.seedKey(SymmetricKey(size: .bits256))
        let settings = LockPolicySettings(suite: UserDefaults(suiteName: "test.vm.\(UUID())")!)
        let vault = VaultManager(keychain: fake, lockPolicy: settings)
        let unlockedBefore = await vault.isUnlocked
        #expect(unlockedBefore == false)
        _ = try await vault.sessionKey()
        let unlockedAfter = await vault.isUnlocked
        #expect(unlockedAfter == true)
        await vault.lockNow()
        let unlockedFinal = await vault.isUnlocked
        #expect(unlockedFinal == false)
    }

    @Test("Immediately policy locks on background entry")
    func immediatelyLocks() async throws {
        let fake = FakeKeychain()
        fake.seedKey(SymmetricKey(size: .bits256))
        let suite = UserDefaults(suiteName: "test.vm.\(UUID())")!
        suite.set(LockPolicy.immediately.rawValue, forKey: StorageKeys.lockPolicy)
        let settings = LockPolicySettings(suite: suite)
        let vault = VaultManager(keychain: fake, lockPolicy: settings)
        _ = try await vault.sessionKey()
        await vault.handleScenePhaseChange(.background)
        let state = await vault.currentState
        #expect(state == .sealed)
    }

    @Test("Non-immediate policy does not lock immediately on background")
    func nonImmediateLeavesUnlocked() async throws {
        let fake = FakeKeychain()
        fake.seedKey(SymmetricKey(size: .bits256))
        let suite = UserDefaults(suiteName: "test.vm.\(UUID())")!
        suite.set(LockPolicy.fiveMinutes.rawValue, forKey: StorageKeys.lockPolicy)
        let settings = LockPolicySettings(suite: suite)
        let vault = VaultManager(keychain: fake, lockPolicy: settings)
        _ = try await vault.sessionKey()
        await vault.handleScenePhaseChange(.background)
        let unlocked = await vault.isUnlocked
        #expect(unlocked == true)
    }

    @Test("Returning active before deadline leaves unlocked")
    func returnActiveBeforeDeadline() async throws {
        let fake = FakeKeychain()
        fake.seedKey(SymmetricKey(size: .bits256))
        let suite = UserDefaults(suiteName: "test.vm.\(UUID())")!
        suite.set(LockPolicy.fiveMinutes.rawValue, forKey: StorageKeys.lockPolicy)
        let settings = LockPolicySettings(suite: suite)
        let vault = VaultManager(keychain: fake, lockPolicy: settings)
        _ = try await vault.sessionKey()
        await vault.handleScenePhaseChange(.background)
        // Pretend 1 second of background passed (well under 5 minute deadline)
        try await Task.sleep(for: .milliseconds(50))
        await vault.handleScenePhaseChange(.active)
        let unlocked = await vault.isUnlocked
        #expect(unlocked == true)
    }

    @Test("Returning active past deadline locks")
    func returnActivePastDeadline() async throws {
        let fake = FakeKeychain()
        fake.seedKey(SymmetricKey(size: .bits256))
        let suite = UserDefaults(suiteName: "test.vm.\(UUID())")!
        // Use a synthetic policy with a near-zero duration via test injection.
        suite.set(LockPolicy.immediately.rawValue, forKey: StorageKeys.lockPolicy)
        // Switch policy to oneMinute mid-test isn't realistic — use the test
        // hook `simulateBackgroundElapsed` documented in the manager.
        let settings = LockPolicySettings(suite: suite)
        settings.current = .fiveMinutes
        let vault = VaultManager(keychain: fake, lockPolicy: settings)
        _ = try await vault.sessionKey()
        await vault.handleScenePhaseChange(.background)
        await vault.simulateBackgroundElapsed(seconds: 600)         // 10 minutes
        await vault.handleScenePhaseChange(.active)
        let state = await vault.currentState
        #expect(state == .sealed)
    }
}
