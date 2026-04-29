# Plan 2 — VaultManager

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `VaultManager` actor — the single owner of the in-memory master key. It serves session-key requests, manages the idle-timer lock policy, transitions through `sealed → unlocking → unlocked → sealed`, and handles `Lock Now` and OS-level biometry lockout.

**Architecture:** Single `actor` for serial state mutation. `LockPolicySettings` is a small `@Observable` `@AppStorage` wrapper. `VaultManager` consults `LockPolicySettings` lazily on each background-entry so policy changes take effect mid-session. The idle timer is a structured `Task` cancelled on resume.

**Tech Stack:** Swift Concurrency (`actor`, `Task`), `@Observable`, `@AppStorage`, `LocalAuthentication` (only via `KeychainService` errors — no direct `LAContext` calls in this layer), `os.Logger`.

**Spec section reference:** §3 (state machine, idle-timer semantics, failed-biometric behaviour, Lock Now).

**Depends on:** Plan 1 (`KeychainService`, `LockPolicy`, `Logger.vault`, `FakeKeychain`).

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Modify | `JournalInsight/AppTheme.swift` | Add `StorageKeys.lockPolicy` constant |
| Create | `JournalInsight/Vault/LockPolicySettings.swift` | `@Observable` AppStorage wrapper around `LockPolicy` |
| Create | `JournalInsight/Vault/VaultError.swift` | Public error type surfaced to repository/views |
| Create | `JournalInsight/Vault/VaultManager.swift` | The actor itself |
| Create | `JournalInsightTests/LockPolicySettingsTests.swift` | Tests for the wrapper |
| Create | `JournalInsightTests/VaultManagerTests.swift` | State-machine + idle-timer + lockNow tests |

---

## Task 1: Add lockPolicy storage key

**Files:**
- Modify: `JournalInsight/AppTheme.swift`

- [x] **Step 1.1: Add `lockPolicy` to `StorageKeys`**

Find the `StorageKeys` enum at the bottom of `AppTheme.swift`. Add one line:

```swift
enum StorageKeys {
    static let userName = "userName"
    static let selectedAppearance = "selectedAppearance"
    static let accentColor = "accentColor"
    static let textSize = "textSize"
    static let notificationsEnabled = "notificationsEnabled"
    static let notificationHour = "notificationHour"
    static let notificationMinute = "notificationMinute"
    static let widgetLayout = "widgetLayout"
    static let lockPolicy = "lockPolicy"        // ← NEW
}
```

- [x] **Step 1.2: Build succeeds**

```
xcodebuild build -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED.

- [x] **Step 1.3: Commit**

```bash
git add JournalInsight/AppTheme.swift
git commit -m "feat(vault): add StorageKeys.lockPolicy"
```

---

## Task 2: LockPolicySettings (@Observable wrapper)

**Files:**
- Create: `JournalInsight/Vault/LockPolicySettings.swift`
- Create: `JournalInsightTests/LockPolicySettingsTests.swift`

- [x] **Step 2.1: Write failing tests**

```swift
// JournalInsightTests/LockPolicySettingsTests.swift
import Testing
import Foundation
@testable import JournalInsight

@Suite("LockPolicySettings")
struct LockPolicySettingsTests {

    @Test("Default value is fiveMinutes when storage is empty")
    func defaultValue() {
        let suite = UserDefaults(suiteName: "test.LockPolicySettings.empty")!
        suite.removeObject(forKey: StorageKeys.lockPolicy)
        let settings = LockPolicySettings(suite: suite)
        #expect(settings.current == .fiveMinutes)
    }

    @Test("Reads stored value")
    func readsStoredValue() {
        let suite = UserDefaults(suiteName: "test.LockPolicySettings.read")!
        suite.set(LockPolicy.oneMinute.rawValue, forKey: StorageKeys.lockPolicy)
        let settings = LockPolicySettings(suite: suite)
        #expect(settings.current == .oneMinute)
    }

    @Test("Writing updates UserDefaults")
    func writesValue() {
        let suite = UserDefaults(suiteName: "test.LockPolicySettings.write")!
        suite.removeObject(forKey: StorageKeys.lockPolicy)
        let settings = LockPolicySettings(suite: suite)
        settings.current = .fifteenMinutes
        #expect(suite.string(forKey: StorageKeys.lockPolicy) == "fifteenMinutes")
    }

    @Test("Falls back to default for unknown raw value")
    func unknownRawValue() {
        let suite = UserDefaults(suiteName: "test.LockPolicySettings.unknown")!
        suite.set("garbage_value", forKey: StorageKeys.lockPolicy)
        let settings = LockPolicySettings(suite: suite)
        #expect(settings.current == .fiveMinutes)
    }
}
```

- [x] **Step 2.2: Run tests to verify they fail**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/LockPolicySettings
```
Expected: FAIL.

- [x] **Step 2.3: Implement LockPolicySettings**

```swift
// JournalInsight/Vault/LockPolicySettings.swift
import Foundation
import Observation

/// `@Observable` wrapper that persists `LockPolicy` to UserDefaults.
/// Injectable suite for tests.
@Observable
final class LockPolicySettings {
    private let suite: UserDefaults

    init(suite: UserDefaults = .standard) {
        self.suite = suite
        // Trigger access tracking by reading once; @Observable observes the
        // computed property below, not the underlying suite.
    }

    var current: LockPolicy {
        get {
            access(keyPath: \.current)
            let raw = suite.string(forKey: StorageKeys.lockPolicy)
            return raw.flatMap(LockPolicy.init(rawValue:)) ?? .fiveMinutes
        }
        set {
            withMutation(keyPath: \.current) {
                suite.set(newValue.rawValue, forKey: StorageKeys.lockPolicy)
            }
        }
    }
}
```

- [x] **Step 2.4: Run tests to verify they pass**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/LockPolicySettings
```
Expected: 4 tests passing.

- [x] **Step 2.5: Commit**

```bash
git add JournalInsight/Vault/LockPolicySettings.swift JournalInsightTests/LockPolicySettingsTests.swift
git commit -m "feat(vault): add @Observable LockPolicySettings persisted to UserDefaults"
```

---

## Task 3: VaultError type

**Files:**
- Create: `JournalInsight/Vault/VaultError.swift`

- [x] **Step 3.1: Create VaultError**

```swift
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
```

- [x] **Step 3.2: Build succeeds**

```
xcodebuild build -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED.

- [x] **Step 3.3: Commit**

```bash
git add JournalInsight/Vault/VaultError.swift
git commit -m "feat(vault): add VaultError public error type"
```

---

## Task 4: VaultManager actor with sessionKey() + lockNow()

**Files:**
- Create: `JournalInsight/Vault/VaultManager.swift`
- Create: `JournalInsightTests/VaultManagerTests.swift`

- [x] **Step 4.1: Write failing tests**

```swift
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
}
```

- [x] **Step 4.2: Run tests to verify they fail**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/VaultManager
```
Expected: FAIL (`VaultManager` not defined).

- [x] **Step 4.3: Implement VaultManager**

```swift
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
    func sessionKey() throws -> SymmetricKey {
        switch state {
        case .unlocked(let key):
            return key
        case .osBlocked:
            throw VaultError.osBlocked
        case .sealed, .unlocking:
            state = .unlocking
            do {
                let key = try awaitSync(keychain.loadMasterKey)
                state = .unlocked(key)
                return key
            } catch KeychainError.itemNotFound {
                // First-time launch — generate a fresh key.
                do {
                    let key = try awaitSync(keychain.storeNewMasterKey)
                    state = .unlocked(key)
                    return key
                } catch KeychainError.userCancelled {
                    state = .sealed
                    throw VaultError.userCancelled
                } catch KeychainError.biometryLockout {
                    state = .osBlocked
                    throw VaultError.osBlocked
                } catch KeychainError.interactionNotAllowed {
                    state = .sealed
                    throw VaultError.iCloudKeychainUnavailable
                } catch {
                    Logger.vault.error("storeNewMasterKey failed: \(error.localizedDescription, privacy: .public)")
                    state = .sealed
                    throw VaultError.keychainUnavailable
                }
            } catch KeychainError.userCancelled {
                state = .sealed
                throw VaultError.userCancelled
            } catch KeychainError.biometryLockout {
                state = .osBlocked
                throw VaultError.osBlocked
            } catch KeychainError.interactionNotAllowed {
                state = .sealed
                throw VaultError.iCloudKeychainUnavailable
            } catch KeychainError.authFailed {
                state = .sealed
                throw VaultError.userCancelled                // map auth-failed to user-driven cancel
            } catch {
                Logger.vault.error("loadMasterKey failed: \(error.localizedDescription, privacy: .public)")
                state = .sealed
                throw VaultError.keychainUnavailable
            }
        }
    }

    func lockNow() {
        idleTask?.cancel()
        idleTask = nil
        lastBackgroundEntry = nil
        state = .sealed
    }

    /// Helper bridging actor body (sync) to async keychain calls.
    /// Each call on the actor is itself in async context, so we stay async-correct.
    private func awaitSync<T>(_ block: () async throws -> T) async rethrows -> T {
        try await block()
    }
}

extension VaultManager {
    /// `sessionKey` declared `throws` rather than `async throws` for the test
    /// fluency above. Provide an async wrapper for callers.
    func sessionKey() async throws -> SymmetricKey {
        let result: SymmetricKey
        do {
            result = try sessionKey()
        }
        return result
    }
}
```

> **Note for the implementer:** Swift `actor` methods are inherently async-callable from outside. The `awaitSync` helper above is an artefact of the test API — collapse it into a single straightforward async method body. The test asserts call counts and state transitions, not the helper structure. The shape below is the intended final form:

```swift
// Final shape — replace the whole VaultManager body with this if Step 4.3 builds awkwardly.
actor VaultManager {

    enum State: Equatable { ... as above ... }

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
```

Use the **final shape** above. Delete the earlier draft.

- [x] **Step 4.4: Run tests to verify they pass**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/VaultManager
```
Expected: 7 tests passing.

- [x] **Step 4.5: Commit**

```bash
git add JournalInsight/Vault/VaultManager.swift JournalInsightTests/VaultManagerTests.swift
git commit -m "feat(vault): add VaultManager actor with sessionKey/lockNow and state machine"
```

---

## Task 5: Idle-timer lock policy + scenePhase wiring

**Files:**
- Modify: `JournalInsight/Vault/VaultManager.swift`
- Modify: `JournalInsightTests/VaultManagerTests.swift`

- [x] **Step 5.1: Append failing tests**

Add these tests to the existing `VaultManagerTests` suite:

```swift
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
    let state = await vault.currentState
    #expect(state == .unlocked)
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
    let state = await vault.currentState
    #expect(state == .unlocked)
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
```

- [x] **Step 5.2: Run tests to verify they fail**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/VaultManager
```
Expected: FAIL (no `handleScenePhaseChange`, `simulateBackgroundElapsed`).

- [x] **Step 5.3: Add idle-timer methods to VaultManager**

Append the following to `VaultManager`:

```swift
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
```

You will also need to import `SwiftUI` if not already (for `ScenePhase`).

- [x] **Step 5.4: Run tests to verify they pass**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/VaultManager
```
Expected: 11 tests passing (7 from Task 4 + 4 new).

- [x] **Step 5.5: Commit**

```bash
git add JournalInsight/Vault/VaultManager.swift JournalInsightTests/VaultManagerTests.swift
git commit -m "feat(vault): wire VaultManager scenePhase handler with idle-timer lock policy"
```

---

## Plan-2 acceptance

- [x] All 4 LockPolicySettings tests pass.
- [x] All 11 VaultManager tests pass.
- [x] `xcodebuild build` succeeds.
- [x] `VaultManager` actor exposes: `sessionKey() async throws -> SymmetricKey`, `lockNow()`, `handleScenePhaseChange(_:) async`, `currentState`, `isUnlocked`.
- [x] No file outside `JournalInsight/Vault/`, `JournalInsight/AppTheme.swift`, or `JournalInsightTests/` is modified.

When all five tasks are checked, this plan is complete.
