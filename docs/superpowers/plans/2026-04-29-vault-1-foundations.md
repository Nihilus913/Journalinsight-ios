# Plan 1 — Vault Foundations

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the stateless cryptographic and policy foundations that every other plan depends on: the AES-GCM envelope codec, the in-memory `EntryBody` plaintext shape, the Keychain abstraction, the `LockPolicy` enum, and the categorised `os.Logger` instances.

**Architecture:** Pure additive — no existing files modified except adding files to the Xcode target. All five components are stateless or value types so they're trivially `Sendable` and unit-testable without SwiftData or biometric stubs. `KeychainService` is a protocol with a production `KeychainStore` and a `FakeKeychain` test double.

**Tech Stack:** SwiftUI, SwiftData, CryptoKit (`AES.GCM`, `SymmetricKey`), Security framework (`SecItem*`), `os.Logger`, Apple Testing framework (`@Suite`/`@Test`/`#expect`).

**Spec section reference:** §1 (Component map), §2 (Envelope), §3 (LockPolicy enum).

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Create | `JournalInsight/Vault/Logger+Categories.swift` | Categorised `os.Logger` singletons (`vault`, `migration`, `sync`, `crypto`, `storage`) |
| Create | `JournalInsight/Vault/EntryBody.swift` | In-memory plaintext shape — `text`, `mood`, `tags`. `Codable`, `Sendable`. |
| Create | `JournalInsight/Vault/LockPolicy.swift` | `LockPolicy` enum with 5 cases + `Duration` mapping |
| Create | `JournalInsight/Vault/KeychainService.swift` | `KeychainService` protocol + production `KeychainStore` impl using iCloud Keychain item |
| Create | `JournalInsight/Vault/EnvelopeCodec.swift` | `AES.GCM`-based encode/decode of `EntryBody` to versioned envelope bytes |
| Create | `JournalInsightTests/EnvelopeCodecTests.swift` | Round-trip, AAD tampering, ciphertext tampering, nonce uniqueness |
| Create | `JournalInsightTests/LockPolicyTests.swift` | Duration mapping, default, all cases distinct |
| Create | `JournalInsightTests/EntryBodyTests.swift` | Codable round-trip, default tags |
| Create | `JournalInsightTests/FakeKeychain.swift` | `FakeKeychain` in-memory `KeychainService` test double (used by Plans 2 + 3) |

---

## Task 1: Logger categories

**Files:**
- Create: `JournalInsight/Vault/Logger+Categories.swift`

- [ ] **Step 1.1: Create the file**

```swift
// JournalInsight/Vault/Logger+Categories.swift
import os

extension Logger {
    static let vault     = Logger(subsystem: "com.tobias.JournalInsight", category: "vault")
    static let migration = Logger(subsystem: "com.tobias.JournalInsight", category: "migration")
    static let sync      = Logger(subsystem: "com.tobias.JournalInsight", category: "sync")
    static let crypto    = Logger(subsystem: "com.tobias.JournalInsight", category: "crypto")
    static let storage   = Logger(subsystem: "com.tobias.JournalInsight", category: "storage")
}
```

- [ ] **Step 1.2: Add file to Xcode target**

In Xcode → File Inspector → Target Membership: ensure `JournalInsight` is checked.

- [ ] **Step 1.3: Build succeeds**

```
xcodebuild build -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 1.4: Commit**

```bash
git add JournalInsight/Vault/Logger+Categories.swift
git commit -m "feat(vault): add categorised os.Logger instances"
```

---

## Task 2: EntryBody

**Files:**
- Create: `JournalInsight/Vault/EntryBody.swift`
- Create: `JournalInsightTests/EntryBodyTests.swift`

- [ ] **Step 2.1: Write failing tests**

```swift
// JournalInsightTests/EntryBodyTests.swift
import Testing
import Foundation
@testable import JournalInsight

@Suite("EntryBody")
struct EntryBodyTests {

    @Test("EntryBody encodes and decodes losslessly")
    func codableRoundTrip() throws {
        let original = EntryBody(text: "Hello", mood: .good, tags: ["one", "two"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EntryBody.self, from: data)
        #expect(decoded.text == original.text)
        #expect(decoded.mood == original.mood)
        #expect(decoded.tags == original.tags)
    }

    @Test("EntryBody with nil mood encodes correctly")
    func nilMood() throws {
        let original = EntryBody(text: "x", mood: nil, tags: [])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EntryBody.self, from: data)
        #expect(decoded.mood == nil)
    }

    @Test("EntryBody preserves tag order")
    func tagOrder() throws {
        let original = EntryBody(text: "x", mood: nil, tags: ["c", "a", "b"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EntryBody.self, from: data)
        #expect(decoded.tags == ["c", "a", "b"])
    }
}
```

- [ ] **Step 2.2: Run tests to verify they fail**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/EntryBody
```
Expected: FAIL (`EntryBody` not defined).

- [ ] **Step 2.3: Create EntryBody**

```swift
// JournalInsight/Vault/EntryBody.swift
import Foundation

/// In-memory plaintext shape of a journal entry. Never persisted directly;
/// only used as input to / output from `EnvelopeCodec`.
struct EntryBody: Codable, Sendable, Equatable {
    var text: String
    var mood: Mood?
    var tags: [String]

    init(text: String, mood: Mood? = nil, tags: [String] = []) {
        self.text = text
        self.mood = mood
        self.tags = tags
    }
}
```

- [ ] **Step 2.4: Run tests to verify they pass**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/EntryBody
```
Expected: 3 tests passing.

- [ ] **Step 2.5: Commit**

```bash
git add JournalInsight/Vault/EntryBody.swift JournalInsightTests/EntryBodyTests.swift
git commit -m "feat(vault): add EntryBody plaintext shape with Codable round-trip tests"
```

---

## Task 3: LockPolicy

**Files:**
- Create: `JournalInsight/Vault/LockPolicy.swift`
- Create: `JournalInsightTests/LockPolicyTests.swift`

- [ ] **Step 3.1: Write failing tests**

```swift
// JournalInsightTests/LockPolicyTests.swift
import Testing
import Foundation
@testable import JournalInsight

@Suite("LockPolicy")
struct LockPolicyTests {

    @Test("Default policy is fiveMinutes")
    func defaultPolicy() {
        #expect(LockPolicy.default == .fiveMinutes)
    }

    @Test("All cases produce distinct durations")
    func distinctDurations() {
        let durations = LockPolicy.allCases.map(\.duration)
        let secondsSet = Set(durations.map { $0.components.seconds })
        #expect(secondsSet.count == LockPolicy.allCases.count)
    }

    @Test("Specific duration values")
    func specificDurations() {
        #expect(LockPolicy.immediately.duration  == .seconds(0))
        #expect(LockPolicy.oneMinute.duration    == .seconds(60))
        #expect(LockPolicy.fiveMinutes.duration  == .seconds(300))
        #expect(LockPolicy.fifteenMinutes.duration == .seconds(900))
        #expect(LockPolicy.oneHour.duration      == .seconds(3600))
    }

    @Test("Raw values are stable strings")
    func rawValuesStable() {
        #expect(LockPolicy.immediately.rawValue    == "immediately")
        #expect(LockPolicy.oneMinute.rawValue      == "oneMinute")
        #expect(LockPolicy.fiveMinutes.rawValue    == "fiveMinutes")
        #expect(LockPolicy.fifteenMinutes.rawValue == "fifteenMinutes")
        #expect(LockPolicy.oneHour.rawValue        == "oneHour")
    }

    @Test("Display label is non-empty for all cases")
    func labels() {
        for policy in LockPolicy.allCases {
            #expect(!policy.displayLabel.isEmpty)
        }
    }
}
```

- [ ] **Step 3.2: Run tests to verify they fail**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/LockPolicy
```
Expected: FAIL (`LockPolicy` not defined).

- [ ] **Step 3.3: Create LockPolicy**

```swift
// JournalInsight/Vault/LockPolicy.swift
import Foundation

/// User-facing policy for how aggressively the in-memory master key
/// is purged from `VaultManager` after the app enters background.
///
/// `immediately` purges the key on every `scenePhase != .active`.
/// All other cases start a timer that fires after the named duration.
enum LockPolicy: String, CaseIterable, Codable, Sendable {
    case immediately
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case oneHour

    static let `default`: LockPolicy = .fiveMinutes

    var duration: Duration {
        switch self {
        case .immediately:    return .seconds(0)
        case .oneMinute:      return .seconds(60)
        case .fiveMinutes:    return .seconds(300)
        case .fifteenMinutes: return .seconds(900)
        case .oneHour:        return .seconds(3600)
        }
    }

    var displayLabel: String {
        switch self {
        case .immediately:    return "Immediately"
        case .oneMinute:      return "After 1 minute"
        case .fiveMinutes:    return "After 5 minutes"
        case .fifteenMinutes: return "After 15 minutes"
        case .oneHour:        return "After 1 hour"
        }
    }
}
```

- [ ] **Step 3.4: Run tests to verify they pass**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/LockPolicy
```
Expected: 5 tests passing.

- [ ] **Step 3.5: Commit**

```bash
git add JournalInsight/Vault/LockPolicy.swift JournalInsightTests/LockPolicyTests.swift
git commit -m "feat(vault): add LockPolicy enum with 5 cases and duration mapping"
```

---

## Task 4: KeychainService protocol + FakeKeychain + production KeychainStore

**Files:**
- Create: `JournalInsight/Vault/KeychainService.swift`
- Create: `JournalInsightTests/FakeKeychain.swift`

- [ ] **Step 4.1: Write the protocol and the production impl**

```swift
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
```

- [ ] **Step 4.2: Write the FakeKeychain test double**

```swift
// JournalInsightTests/FakeKeychain.swift
import Foundation
import CryptoKit
@testable import JournalInsight

/// In-memory KeychainService for unit tests. Configurable to throw at any step.
final class FakeKeychain: KeychainService, @unchecked Sendable {
    private let lock = NSLock()
    private var storedKey: SymmetricKey?

    /// If set, loadMasterKey throws this error instead of returning the stored key.
    var loadError: KeychainError?
    /// If set, storeNewMasterKey throws this error instead of generating one.
    var storeError: KeychainError?
    /// Tracks call counts for assertion in tests.
    private(set) var loadCallCount = 0
    private(set) var storeCallCount = 0

    func loadMasterKey() async throws -> SymmetricKey {
        lock.lock(); defer { lock.unlock() }
        loadCallCount += 1
        if let error = loadError { throw error }
        guard let key = storedKey else { throw KeychainError.itemNotFound }
        return key
    }

    func storeNewMasterKey() async throws -> SymmetricKey {
        lock.lock(); defer { lock.unlock() }
        storeCallCount += 1
        if let error = storeError { throw error }
        let key = SymmetricKey(size: .bits256)
        storedKey = key
        return key
    }

    func deleteMasterKey() async throws {
        lock.lock(); defer { lock.unlock() }
        storedKey = nil
    }

    /// Test helper — pre-seed a known key for round-trip testing.
    func seedKey(_ key: SymmetricKey) {
        lock.lock(); defer { lock.unlock() }
        storedKey = key
    }
}
```

- [ ] **Step 4.3: Build succeeds**

```
xcodebuild build -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED. (No tests yet; production `KeychainStore` requires biometric so it can't be unit-tested. Plan 2's VaultManager tests exercise the FakeKeychain.)

- [ ] **Step 4.4: Commit**

```bash
git add JournalInsight/Vault/KeychainService.swift JournalInsightTests/FakeKeychain.swift
git commit -m "feat(vault): add KeychainService protocol with iCloud-Keychain backed production impl and FakeKeychain test double"
```

---

## Task 5: EnvelopeCodec

**Files:**
- Create: `JournalInsight/Vault/EnvelopeCodec.swift`
- Create: `JournalInsightTests/EnvelopeCodecTests.swift`

- [ ] **Step 5.1: Write failing tests**

```swift
// JournalInsightTests/EnvelopeCodecTests.swift
import Testing
import Foundation
import CryptoKit
@testable import JournalInsight

@Suite("EnvelopeCodec")
struct EnvelopeCodecTests {
    private let key = SymmetricKey(size: .bits256)
    private let entryID = UUID()

    @Test("encode then decode produces same EntryBody")
    func roundTrip() throws {
        let original = EntryBody(text: "hello world", mood: .good, tags: ["a", "b"])
        let envelope = try EnvelopeCodec.encode(original, key: key, entryID: entryID, schemaVersion: 1)
        let decoded = try EnvelopeCodec.decode(envelope.cipher, key: key, entryID: entryID, schemaVersion: 1)
        #expect(decoded == original)
    }

    @Test("decode with wrong key throws decryptionFailed")
    func wrongKey() throws {
        let body = EntryBody(text: "x")
        let envelope = try EnvelopeCodec.encode(body, key: key, entryID: entryID, schemaVersion: 1)
        let wrongKey = SymmetricKey(size: .bits256)
        #expect(throws: EnvelopeError.decryptionFailed) {
            _ = try EnvelopeCodec.decode(envelope.cipher, key: wrongKey, entryID: entryID, schemaVersion: 1)
        }
    }

    @Test("decode with tampered ciphertext throws")
    func tamperedCiphertext() throws {
        let body = EntryBody(text: "hello")
        let envelope = try EnvelopeCodec.encode(body, key: key, entryID: entryID, schemaVersion: 1)
        var tampered = envelope.cipher
        // Flip a byte deep in the ciphertext (past version byte + nonce + first data byte)
        let flipIndex = tampered.count - 5
        tampered[flipIndex] ^= 0xFF
        #expect(throws: EnvelopeError.decryptionFailed) {
            _ = try EnvelopeCodec.decode(tampered, key: key, entryID: entryID, schemaVersion: 1)
        }
    }

    @Test("decode with mismatched entry ID (AAD) throws")
    func aadEntryIDMismatch() throws {
        let body = EntryBody(text: "hello")
        let envelope = try EnvelopeCodec.encode(body, key: key, entryID: entryID, schemaVersion: 1)
        let differentID = UUID()
        #expect(throws: EnvelopeError.decryptionFailed) {
            _ = try EnvelopeCodec.decode(envelope.cipher, key: key, entryID: differentID, schemaVersion: 1)
        }
    }

    @Test("decode with mismatched schemaVersion throws")
    func aadSchemaVersionMismatch() throws {
        let body = EntryBody(text: "hello")
        let envelope = try EnvelopeCodec.encode(body, key: key, entryID: entryID, schemaVersion: 1)
        #expect(throws: EnvelopeError.decryptionFailed) {
            _ = try EnvelopeCodec.decode(envelope.cipher, key: key, entryID: entryID, schemaVersion: 2)
        }
    }

    @Test("two encodes of same body produce different ciphertexts")
    func nonceUniqueness() throws {
        let body = EntryBody(text: "same")
        let e1 = try EnvelopeCodec.encode(body, key: key, entryID: entryID, schemaVersion: 1)
        let e2 = try EnvelopeCodec.encode(body, key: key, entryID: entryID, schemaVersion: 1)
        #expect(e1.cipher != e2.cipher)
        #expect(e1.nonce != e2.nonce)
    }

    @Test("envelope starts with version byte 0x01")
    func versionByte() throws {
        let body = EntryBody(text: "x")
        let envelope = try EnvelopeCodec.encode(body, key: key, entryID: entryID, schemaVersion: 1)
        #expect(envelope.cipher.first == 0x01)
    }

    @Test("nonce is 12 bytes")
    func nonceLength() throws {
        let body = EntryBody(text: "x")
        let envelope = try EnvelopeCodec.encode(body, key: key, entryID: entryID, schemaVersion: 1)
        #expect(envelope.nonce.count == 12)
    }

    @Test("decode rejects unknown version byte")
    func unknownVersion() throws {
        let body = EntryBody(text: "x")
        var envelope = try EnvelopeCodec.encode(body, key: key, entryID: entryID, schemaVersion: 1)
        envelope.cipher[0] = 0xFF                       // unknown version
        #expect(throws: EnvelopeError.unsupportedVersion(0xFF)) {
            _ = try EnvelopeCodec.decode(envelope.cipher, key: key, entryID: entryID, schemaVersion: 1)
        }
    }
}
```

- [ ] **Step 5.2: Run tests to verify they fail**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/EnvelopeCodec
```
Expected: FAIL (`EnvelopeCodec` not defined).

- [ ] **Step 5.3: Create EnvelopeCodec**

```swift
// JournalInsight/Vault/EnvelopeCodec.swift
import Foundation
import CryptoKit
import os

enum EnvelopeError: Error, Equatable {
    case decryptionFailed
    case unsupportedVersion(UInt8)
    case malformed
}

/// Versioned AES-256-GCM envelope codec. Wire format:
///
///   byte 0:        version (currently 0x01)
///   bytes 1...12:  nonce (12 bytes)
///   bytes 13...:   sealed-box ciphertext + 16-byte GCM tag
///
/// AAD: entryID.uuidString.utf8 || schemaVersion.littleEndianBytes
/// Re-associating ciphertext to a different entry/version triggers GCM auth failure.
enum EnvelopeCodec {
    static let currentVersion: UInt8 = 0x01

    struct Envelope {
        var cipher: Data
        var nonce: Data
    }

    static func encode(
        _ body: EntryBody,
        key: SymmetricKey,
        entryID: UUID,
        schemaVersion: Int
    ) throws -> Envelope {
        let plaintext = try JSONEncoder().encode(body)
        let aad = makeAAD(entryID: entryID, schemaVersion: schemaVersion)
        let nonce = AES.GCM.Nonce()
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
        } catch {
            Logger.crypto.error("seal failed: \(error.localizedDescription, privacy: .public)")
            throw EnvelopeError.decryptionFailed
        }
        var bytes = Data()
        bytes.append(currentVersion)
        bytes.append(contentsOf: nonce)
        bytes.append(sealed.ciphertext)
        bytes.append(sealed.tag)
        return Envelope(cipher: bytes, nonce: Data(nonce))
    }

    static func decode(
        _ data: Data,
        key: SymmetricKey,
        entryID: UUID,
        schemaVersion: Int
    ) throws -> EntryBody {
        guard let firstByte = data.first else { throw EnvelopeError.malformed }
        guard firstByte == currentVersion else { throw EnvelopeError.unsupportedVersion(firstByte) }
        guard data.count >= 1 + 12 + 16 else { throw EnvelopeError.malformed }
        let nonceBytes = data.subdata(in: 1..<13)
        let tagStart = data.count - 16
        let ciphertext = data.subdata(in: 13..<tagStart)
        let tag = data.subdata(in: tagStart..<data.count)
        let nonce: AES.GCM.Nonce
        do {
            nonce = try AES.GCM.Nonce(data: nonceBytes)
        } catch {
            throw EnvelopeError.malformed
        }
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        } catch {
            throw EnvelopeError.malformed
        }
        let aad = makeAAD(entryID: entryID, schemaVersion: schemaVersion)
        do {
            let plaintext = try AES.GCM.open(sealed, using: key, authenticating: aad)
            return try JSONDecoder().decode(EntryBody.self, from: plaintext)
        } catch is CryptoKitError {
            throw EnvelopeError.decryptionFailed
        } catch is DecodingError {
            throw EnvelopeError.decryptionFailed
        } catch {
            throw EnvelopeError.decryptionFailed
        }
    }

    private static func makeAAD(entryID: UUID, schemaVersion: Int) -> Data {
        var aad = Data()
        aad.append(entryID.uuidString.data(using: .utf8) ?? Data())
        var schemaLE = Int32(schemaVersion).littleEndian
        withUnsafeBytes(of: &schemaLE) { aad.append(contentsOf: $0) }
        return aad
    }
}
```

- [ ] **Step 5.4: Run tests to verify they pass**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/EnvelopeCodec
```
Expected: 9 tests passing.

- [ ] **Step 5.5: Commit**

```bash
git add JournalInsight/Vault/EnvelopeCodec.swift JournalInsightTests/EnvelopeCodecTests.swift
git commit -m "feat(vault): add EnvelopeCodec with AES-256-GCM and AAD-bound entry ID + schema version"
```

---

## Plan-1 acceptance

- [ ] All 9 EnvelopeCodec tests pass.
- [ ] All 3 EntryBody tests pass.
- [ ] All 5 LockPolicy tests pass.
- [ ] `xcodebuild build` succeeds for the whole scheme.
- [ ] No new files outside `JournalInsight/Vault/` and `JournalInsightTests/`.
- [ ] All commits use the `feat(vault):` prefix.

When all five tasks are checked, this plan is complete. Worker subagent reports final commit SHA.
