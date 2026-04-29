# Encrypted Vault — Option D / v1.0 Design

**Date:** 2026-04-29
**Project:** JournalInsight iOS
**Status:** Approved for implementation planning
**Supersedes:** Audit findings C-1, C-2, C-3, H-5, H-7, H-10, S-1 → S-7, S-9, S-10 from `CODE_REVIEW.html`

---

## Context

JournalInsight stores personal journal-grade content (free-text reflections, mood states, prompt responses, tag labels). Today the app uses default-protection SwiftData with no app-level encryption, advertises iCloud sync that isn't actually wired up, and has a tag-uniqueness constraint that can crash the app on a duplicate-name insert. The most recent code review (`CODE_REVIEW.html`) identifies these as critical issues.

This spec defines the v1.0 release that closes those gaps in a single coherent change: an end-to-end encrypted journal with iCloud sync, biometric app-lock, and a clean migration from the current plaintext store.

The user-visible promise is **"Your entries are encrypted on this device. Apple sees only encrypted data on iCloud."**

---

## Decisions

The design rests on six earlier decisions, captured here as the source of truth:

| # | Decision | Choice |
|---|---|---|
| 1 | Release strategy | Skip a separate "iOS-native floor" release; ship one v1.0 that includes the floor *and* the encrypted-body model |
| 2 | Sync scope | iCloud sync, end-to-end encrypted from Apple's perspective |
| 3 | Master key location | iCloud Keychain (`kSecAttrSynchronizable = true`, `.biometryCurrentSet` ACL). No user passphrase. |
| 4 | Encryption scope | `text` + `mood` + tag-name list encrypted. `date` and `duration` stay plaintext on CloudKit so widgets/calendar/streak work without unlock. |
| 5 | Lock policy | Idle timeout, configurable: Immediately / 1 min / 5 min (default) / 15 min / 1 hour. No "off" option. |
| 6 | Migration path | Clean break — schema migration adds new columns, content migration encrypts in place with a one-time biometric-gated screen, container swaps to CloudKit-enabled after migration completes. |

Goals stay plaintext under `.complete` file protection (no app-level encryption). All `Tag` instances are deleted at the end of v1.0 migration; tag names live inside each entry's encrypted payload from then on. The `Tag` SwiftData entity itself remains in the v1.0 schema (still needed by Stage 2 to read legacy data) and is removed by the v1.1 cleanup migration.

### Goals

- All journal text, mood, and tag content unreadable to Apple, attackers with iCloud-account access, and forensic tooling against an unlocked Finder backup.
- Glanceable widgets (streak, count, calendar dots) keep working without biometric unlock.
- Zero-friction onboarding — no passphrase, no recovery code; iCloud Keychain handles key transport.
- Resolves audit findings C-1, C-2, C-3 fully, plus H-5, H-7, H-10, S-1 → S-7, S-9, S-10 partially or fully.

### Non-goals (deferred)

- User-passphrase-derived "paranoid mode" for true zero-knowledge against Apple. Considered and rejected for v1 due to recovery-UX cost.
- Encrypted export format (the existing CSV/JSON export is and stays plaintext, with a clear in-UI warning).
- macOS Catalyst / iPadOS-specific layouts.
- Per-entry sharing with separate keys.
- iPad/macOS-specific surfaces.
- About section in Settings (the privacy-policy URL itself is still required for App Store submission).

---

## Section 1 — Architecture overview

### Component map

| Component | Type | Responsibility |
|---|---|---|
| `VaultManager` | `actor` | Master-key lifecycle. Holds the in-memory cached key after biometric unlock; clears it on idle timeout, manual lock, or biometric ACL invalidation. Owns the lock-policy timer. |
| `EnvelopeCodec` | value type, `Sendable` | Encodes/decodes the on-disk ciphertext envelope (version byte + nonce + AAD + ciphertext + GCM tag). Pure function of `(masterKey, plaintext)`. No state. |
| `EntryRepository` | `@MainActor struct` | Thin SwiftUI-facing surface. `body(for: entry) async throws -> EntryBody` and `save(_:) async throws`. Views never touch `VaultManager` directly. |
| `MigrationCoordinator` | `@MainActor` | Runs once when the persisted schema version transitions from `0` to `1`. Per-entry transactional encryption with idempotent restart. |
| `PrivacyOverlay` | view modifier | Draws an opaque redacted layer when `scenePhase != .active`. Always-on, no toggle. |
| `LockPolicySettings` | `@Observable` | `@AppStorage`-backed; exposes the current `LockPolicy` to `VaultManager`. |
| `SyncStatusObserver` | `@MainActor @Observable` | Maps `NSPersistentCloudKitContainer.eventChangedNotification` to a small `SyncStatus` enum surfaced in UI. |

### Data flow on entry read

```
SwiftUI View
   │  body = await repo.body(for: entry)
   ▼
EntryRepository (@MainActor)
   │  let key = try await vault.sessionKey()
   ▼
VaultManager (actor)
   │  if cached key valid → return it
   │  else → request Keychain item with biometric ACL → user authenticates →
   │         cache key, start/refresh idle timer → return it
   ▼
EnvelopeCodec.decode(entry.bodyCipher, nonce: entry.nonce, key: key, aad: entry.aad)
   │
   ▼  EntryBody { text, mood, tags }
```

### Plaintext lifetime

Plaintext exists only in process memory between the moment `EnvelopeCodec.decode` returns and the moment the calling view goes out of scope. It is never written to disk, never logged, never put on the pasteboard automatically. (System `TextEditor` copy is still a user gesture and unavoidable; flagged as accepted.)

### Trust boundaries

- **CloudKit servers** see exactly: `JournalEntry.id`, `date`, `duration`, `bodyCipher` (opaque), `nonce`, `schemaVersion`. Plus the `Goal` table in plaintext (per decision #4).
- **Local SwiftData store** contains the same fields. The plaintext `text` column does not exist after migration (see Section 4 cleanup roadmap).
- **Master key** lives in iCloud Keychain only. Never written to disk, never logged, never sent to CloudKit.

### Concurrency model

- `VaultManager` is an `actor` — single serial executor; the master key is never racily read or cleared.
- `EntryRepository` is `@MainActor` — SwiftUI updates stay on main without `MainActor.run` boilerplate.
- `EnvelopeCodec` is stateless and `Sendable`, can run on any executor.

### File layout

```
Vault/
  VaultManager.swift
  EnvelopeCodec.swift
  EntryBody.swift
  LockPolicy.swift                   (enum + AppStorage helper)
  PrivacyOverlay.swift
  KeychainService.swift              (protocol + production impl; testable)
Migration/
  MigrationCoordinator.swift
  MigrationSheet.swift               (UI)
Repositories/
  EntryRepository.swift
Storage/
  SchemaVersions.swift               (V0, V1 versioned schemas + plan)
Sync/
  SyncStatusObserver.swift
  SyncStatusView.swift               (toolbar icon + Settings indicator)
```

### Modified existing files

`JournalEntry.swift`, `JournalInsightApp.swift`, `MainScreenView.swift`, `CalendarDetailView.swift`, `SessionDetailView.swift`, `StreakDetailView.swift`, `SettingsView.swift`, `Goal.swift` (no encryption — plaintext per decision), tests.

### Removed instances / references in v1.0

- All `Tag` instances are deleted at the end of Stage 2 migration. The `Tag` model type stays in the v1.0 schema (referenced by `JournalSchemaV1.models`) so SwiftData can still open existing stores during Stage 2.
- All `Tag`-related view code in `MainScreenView.swift` is removed — tag editing UI now reads/writes the `[String]` array inside `EntryBody` instead of the SwiftData entity.

### Removed in v1.1 cleanup migration (Stage 3)

- The `Tag` SwiftData entity itself.
- The `text` and `moodRaw` columns on `JournalEntry`.

---

## Section 2 — Schema, files, and key hierarchy

### Final SwiftData schema (post-migration)

```swift
@Model
final class JournalEntry {
    var id: UUID = UUID()                       // plaintext, sync
    var date: Date = Date()                     // plaintext, sync
    var duration: TimeInterval = 0              // plaintext, sync
    var bodyCipher: Data = Data()               // CIPHERTEXT, sync — encrypted EntryBody
    var nonce: Data = Data()                    // plaintext (12 bytes, random per encryption)
    var schemaVersion: Int = 1                  // plaintext — gates envelope rotation; -1 = quarantine
}

struct EntryBody: Codable, Sendable {           // never persisted — only in-memory
    var text: String
    var mood: Mood?
    var tags: [String]                          // tag names embedded; no Tag entity
}

@Model
final class Goal {                              // unchanged from today
    var id: UUID = UUID()
    var title: String = ""
    var targetDate: Date = Date()
    var progress: Double = 0
}
```

Three notes:

- `@Attribute(.unique)` is dropped everywhere — incompatible with CloudKit. UUID collision resistance carries the load. Closes audit C-1.
- All properties have defaults — required by CloudKit + SwiftData.
- `Mood` stays a `Codable` enum but moves *inside* the encrypted JSON payload (used to be `JournalEntry.moodRaw` raw column).

### File-system layout

| Path | Contents | Protection | Excluded from backup |
|---|---|---|---|
| `~/Library/Application Support/default.store` | SwiftData SQLite (+ `-shm`, `-wal`) | `.complete` | No (CloudKit replaces backup) |
| `~/Documents/wallpaper.dat` | User-uploaded wallpaper | `.complete` | Yes (large blob, regenerable) |
| `~/Library/Caches/JournalInsight/Exports/` | CSV/JSON export staging | `.complete` | Yes |

The SwiftData store moves from default `Documents` into `Application Support` via `ModelConfiguration(url:)` so it is not user-visible in the Files app. File protection is set by writing the `.protectionKey` attribute at first-launch *before* opening the store, then verified by a debug-only assertion at launch.

### Master-key Keychain item

```swift
let acl = SecAccessControlCreateWithFlags(
    nil,
    kSecAttrAccessibleWhenUnlocked,           // required for synchronizable=true
    .biometryCurrentSet,                      // invalidates on biometric re-enroll
    nil
)

let attributes: [String: Any] = [
    kSecClass as String:              kSecClassGenericPassword,
    kSecAttrService as String:        "com.tobias.JournalInsight",
    kSecAttrAccount as String:        "vault.master",
    kSecAttrSynchronizable as String: true,    // iCloud Keychain
    kSecAttrAccessControl as String:  acl!,
    kSecValueData as String:          keyBytes // 32 random bytes
]
```

Three deliberate ACL choices:

1. `kSecAttrAccessibleWhenUnlocked` (not `WhenUnlockedThisDeviceOnly`) — iCloud Keychain refuses to sync `ThisDeviceOnly` items. We accept that the key is accessible while the device is unlocked; the biometric flag still gates *retrieval*.
2. `.biometryCurrentSet` — if the user re-enrolls Face ID or adds a new fingerprint, the local key copy is invalidated. Recovery is automatic: iCloud Keychain refetches from another paired device. If no other device exists, the user goes through device-passcode unlock; the app re-fetches via iCloud Keychain HSM escrow.
3. **No `.biometryAny` fallback to passcode-only access on this item** — passcode falls through Apple's iCloud Keychain HSM escrow on a clean device; we don't implement a second app-level recovery path.

**Key generation:** On first launch, if `SecItemCopyMatching` returns `errSecItemNotFound` *and* iCloud Keychain hasn't yet synced one in, we generate 32 random bytes via `SecRandomCopyBytes` and store with the attributes above. iCloud Keychain replicates to other devices automatically.

**iCloud Keychain unavailable case.** If the device has iCloud Keychain disabled, `kSecAttrSynchronizable=true` items still store locally but never sync. Detection: surface an `iCloudKeychainUnavailable` error and a settings sheet explaining the requirement (Section 6 error taxonomy).

### Encryption envelope

CryptoKit `AES-256-GCM` with this on-disk byte layout:

```
[ 1 byte  | version (currently 0x01)                          ]
[12 bytes | nonce (also mirrored to JournalEntry.nonce column) ]
[ N bytes | ciphertext                                          ]
[16 bytes | GCM authentication tag                              ]
```

**AAD:** `entry.id.uuidString.utf8 || schemaVersion.littleEndian`. Attaching ciphertext to a different entry row triggers GCM auth failure.

The `JournalEntry.nonce` column duplicates the envelope's nonce bytes so SwiftData/CloudKit can include it in records without parsing the envelope. Source of truth on decode is the envelope itself.

### CloudKit configuration

```swift
let schema = Schema([JournalEntry.self, Goal.self])
let cfg = ModelConfiguration(
    schema: schema,
    url: URL.applicationSupportDirectory.appending(path: "default.store"),
    cloudKitDatabase: .private("iCloud.com.tobias.JournalInsight")
)
```

Wire payload per `JournalEntry`: `id`, `date`, `duration`, `bodyCipher` (opaque), `nonce`, `schemaVersion`. Conflict resolution: SwiftData's default last-writer-wins. `bodyCipher` is one atomic blob, so partial-field merging is mathematically impossible on ciphertext; last-writer-wins is the correct (only) policy.

---

## Section 3 — VaultManager state machine and lock policy

### State machine

```swift
actor VaultManager {
    enum State {
        case sealed                                 // no key in memory
        case unlocking                              // biometric prompt in flight
        case unlocked(SymmetricKey, idleTask: Task<Void, Never>)
        case osBlocked                              // LAError.biometryLockout etc.
    }

    private var state: State = .sealed
    private let lockPolicy: LockPolicySettings      // observable @AppStorage
    private let keychain: KeychainService           // protocol — testable
    private var lastBackgroundEntry: Date?

    func sessionKey() async throws -> SymmetricKey
    func lockNow() async                            // Lock-Now button
    func handleScenePhaseChange(_ phase: ScenePhase) async
    var isUnlocked: Bool { get }
}
```

### Transitions

| From | Trigger | To |
|---|---|---|
| `sealed` | `sessionKey()` called | `unlocking` |
| `unlocking` | biometric succeeds → key fetched from Keychain | `unlocked(key, task)` |
| `unlocking` | user cancels biometric / `errUserCancel` | `sealed` |
| `unlocking` | `LAError.biometryLockout` after OS-level retry budget | `osBlocked` |
| `unlocked` | idle task fires after timeout in background | `sealed` |
| `unlocked` | `lockNow()` invoked | `sealed` |
| `unlocked` | `kSecAttrAccessControl` invalidated (biometric re-enroll) | `sealed` |
| `osBlocked` | iOS releases the lockout (next successful device-passcode unlock) | `sealed` |

### Idle-timer semantics

The timeout counts **background wall-clock time only**. Foreground use does not tick.

```
scenePhase → .background:
    if policy == .immediately { lockNow() }
    else {
        lastBackgroundEntry = Date()
        idleTask = Task { try? await Task.sleep(for: policy.duration); await lockNow() }
    }

scenePhase → .active:
    idleTask?.cancel()
    if let last = lastBackgroundEntry,
       Date().timeIntervalSince(last) >= policy.duration {
        await lockNow()                              // belt-and-suspenders for iOS suspension
    }
    lastBackgroundEntry = nil
```

The `Task.sleep`-while-in-background is the belt; the on-resume comparison is the suspenders. iOS may kill the sleeping task at any point during background; the resume check guarantees correctness.

### `LockPolicySettings`

```swift
enum LockPolicy: String, CaseIterable, Codable {
    case immediately        // lock on .background
    case oneMinute          // 60 s
    case fiveMinutes        // 300 s — DEFAULT
    case fifteenMinutes     // 900 s
    case oneHour            // 3600 s

    var duration: Duration { ... }
}

@Observable
final class LockPolicySettings {
    @ObservationIgnored
    @AppStorage(StorageKeys.lockPolicy) private var raw: String = LockPolicy.fiveMinutes.rawValue
    var current: LockPolicy { get set }
}
```

The Settings picker binds to this; `VaultManager` reads `current` lazily on each background-entry, so changing the policy mid-session takes effect immediately without restart.

### Failed-biometric behaviour

We do **not** implement an app-level retry counter. iOS already enforces:

1. Face ID / Touch ID: 5 failed attempts → passcode fallback.
2. Passcode: progressive delays managed by SpringBoard.
3. After enough failures: `LAError.biometryLockout`.

`VaultManager` maps `LAError.biometryLockout` to `state = .osBlocked` and the calling view shows: *"Face ID is temporarily disabled. Unlock your iPhone to retry."* No app-level lockout counter (would only duplicate iOS logic and create a forgeable `UserDefaults`-stored counter).

### `EntryRepository` + view interaction

Views never see `.sealed` / `.unlocking` / `.osBlocked` directly. The repository exposes one async function:

```swift
func body(for entry: JournalEntry) async throws -> EntryBody
// Throws: VaultError.userCancelled, .osBlocked, .decryptionFailed
```

When a view call throws `.userCancelled`, the row UI shows a redacted placeholder with a **"🔒 Tap to unlock"** pill. SwiftUI re-renders on state change because `LockPolicySettings` is `@Observable` and the repository observes it.

### Manual `Lock Now`

Surfaced in **Settings → Privacy & Lock → "Lock Now" row**. (Three-finger-tap gesture and toolbar long-press considered and rejected for v1.0.)

`Lock Now`: `await vault.lockNow()` → state goes to `.sealed` → views observing `vault.isUnlocked` re-render to placeholders.

### Privacy overlay (orthogonal)

`PrivacyOverlay` is **not** gated on vault state. It always covers the UI when `scenePhase != .active`, regardless of whether the vault is unlocked. This protects against the app-switcher snapshot leak (audit S-2), which can happen even mid-session while the vault holds a valid key.

---

## Section 4 — Migration flow

### Two-stage migration model

| Stage | When | Needs biometric | Touches CloudKit | Removed in |
|---|---|---|---|---|
| 1 — Schema migration | At container init on first v1.0 launch | No | No | (permanent) |
| 2 — Content migration | After Stage 1, gated by user-driven biometric | Yes | No (CloudKit disabled until complete) | (permanent) |
| 3 — Cleanup migration | v1.1 | No | Yes | v1.1 release |

### Stage 1 — Additive SwiftData schema migration

```swift
enum JournalSchemaV0: VersionedSchema {
    static var versionIdentifier = Schema.Version(0, 0, 0)
    static var models: [any PersistentModel.Type] = [V0.JournalEntry.self, V0.Goal.self, V0.Tag.self]
}

enum JournalSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    // JournalEntry gains: bodyCipher, nonce, schemaVersion
    // text, moodRaw kept temporarily (read by Stage 2; emptied after)
    // Tag kept temporarily (read in Stage 2; instances deleted after)
    static var models: [any PersistentModel.Type] = [JournalEntry.self, Goal.self, Tag.self]
}

enum JournalMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [JournalSchemaV0.self, JournalSchemaV1.self]
    static let stages: [MigrationStage] = [
        .lightweight(fromVersion: JournalSchemaV0.self, toVersion: JournalSchemaV1.self)
    ]
}
```

Lightweight — SwiftData handles it without custom code because new columns have defaults (`Data()`, `Data()`, `0`). Runs at container init in milliseconds.

### Stage 2 — Content migration

```swift
@MainActor
struct MigrationCoordinator {
    static func pendingCount(in ctx: ModelContext) throws -> Int    // schemaVersion == 0
    static func quarantineCount(in ctx: ModelContext) throws -> Int // schemaVersion == -1

    static func run(
        in ctx: ModelContext,
        vault: VaultManager,
        progress: @MainActor (Int, Int) -> Void
    ) async throws
}
```

**Per-entry algorithm** (idempotent and transactional):

```swift
let pending = try ctx.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.schemaVersion == 0 }))
let total = pending.count
let key = try await vault.sessionKey()                 // single biometric prompt for the whole batch
for (i, entry) in pending.enumerated() {
    do {
        try ctx.transaction {
            let body = EntryBody(
                text: entry.text ?? "",
                mood: entry.moodRaw.flatMap(Mood.init(rawValue:)),
                tags: entry.tags?.map(\.name) ?? []
            )
            let envelope = try EnvelopeCodec.encode(body, key: key, aad: AAD(id: entry.id, version: 1))
            entry.bodyCipher    = envelope.cipher
            entry.nonce         = envelope.nonce
            entry.schemaVersion = 1
            entry.text          = nil
            entry.moodRaw       = nil
            entry.tags          = []
        }
    } catch {
        Logger.migration.error("quarantine entry=\(entry.id, privacy: .private(mask: .hash)) " +
                               "reason=\(error.localizedDescription, privacy: .public)")
        try ctx.transaction { entry.schemaVersion = -1 }
    }
    progress(i + 1, total)
}
// All entries done — orphan Tag rows deleted
try ctx.transaction {
    for tag in try ctx.fetch(FetchDescriptor<Tag>()) { ctx.delete(tag) }
}
```

Each entry's encryption is its own `ctx.transaction { }` block. Mid-migration kill leaves a consistent partial state. On next launch, `pendingCount` returns whatever didn't finish; the user re-prompts biometric and resumes.

### Why CloudKit is off during Stage 2

If CloudKit were enabled while v0 rows exist, those rows would replicate to iCloud with `text` and `moodRaw` populated as plaintext for the seconds-to-minutes between Stage 1 completing and Stage 2 finishing. That defeats the entire encryption release. So we sequence:

```
App launch
  ↓
Build PRE-MIGRATION ModelContainer        ← cloudKitDatabase: .none
  ↓
Stage 1 (schema migration, automatic)
  ↓
pendingCount > 0?
  ├─ no  → swap to FINAL ModelContainer with CloudKit, present dashboard
  └─ yes → present MigrationSheet
              ↓
              biometric → Stage 2 (content migration, with progress bar)
              ↓
              tear down PRE-MIGRATION container
              ↓
              build FINAL ModelContainer with cloudKitDatabase: .private(...)
              ↓
              dismiss sheet, present dashboard
```

The container swap is implemented by holding `@State private var container: ModelContainer?` in `JournalInsightApp`. Both containers point to the same on-disk SQLite file at `~/Library/Application Support/default.store`; only the CloudKit binding differs. Swap safety **must be validated by a focused integration test before release** (item #8 in the pre-release security gate).

### Migration UI

A dedicated full-screen `MigrationSheet` over a splash background. Four states:

| State | UI |
|---|---|
| `Idle` (intro) | Headline: *"Setting up encrypted storage."* Body: *"Your journal is moving to encrypted, end-to-end iCloud storage. This takes a few seconds. Tap Continue to authenticate."* CTA: *Continue.* |
| `Encrypting` | Progress bar `currentEntry / totalEntries`. Subtext: *"Encrypting entry %d of %d…"* No cancel button. (Quitting the app is the escape hatch; resumes on relaunch.) |
| `Done` | Brief checkmark; auto-dismiss after 0.8 s. |
| `Failed` (rare) | *"Migration paused. Some entries couldn't be encrypted. Tap Retry."* Surfaces underlying error code. |

### Edge cases

- **Empty database (brand-new install).** `pendingCount == 0`. Skip Stage 2 entirely; build CloudKit container directly.
- **Second device on same iCloud account before first device has migrated.** Second device's local DB is empty, CloudKit container is empty, `pendingCount == 0`. Skip Stage 2. Once first device finishes Stage 2 and begins syncing, second device pulls down v1 rows directly. Zero plaintext exposure.
- **Mid-migration biometric ACL invalidation.** User re-enrolls Face ID at the worst moment. Next per-entry `vault.sessionKey()` throws; we abort the in-flight transaction (no row half-encrypted), present `Failed`, user re-authenticates, resume.
- **Single failed entry (decode of legacy data fails).** Quarantine: `schemaVersion = -1`. End of migration: surface a banner *"%d entries couldn't be migrated. Tap to review."* User-driven manual fix path.
- **App backgrounded mid-migration.** iOS gives ~30 s of background runtime; on suspend we cleanly finish the current row's transaction, then on resume the loop continues from `pendingCount`. If iOS terminates us, the next launch resumes.

### Cleanup migration (v1.1, documented now)

```swift
.custom(
    fromVersion: JournalSchemaV1.self,
    toVersion: JournalSchemaV2.self,
    willMigrate: { ctx in
        // assert: try ctx.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.schemaVersion == 0 })).isEmpty
    },
    didMigrate: nil
)
```

`JournalSchemaV2` drops `text`, `moodRaw`, and the entire `Tag` model. Documented now so it is not forgotten.

---

## Section 5 — CloudKit sync, settings UI, and iOS hardening floor

### CloudKit configuration — required project changes

| Item | Where | Value |
|---|---|---|
| Capability | Xcode → Signing & Capabilities | iCloud (CloudKit, container `iCloud.com.tobias.JournalInsight`) |
| Capability | Xcode → Signing & Capabilities | Background Modes → Remote notifications |
| Capability | Xcode → Signing & Capabilities | Push Notifications |
| Entitlement | `JournalInsight.entitlements` | `com.apple.developer.icloud-services = CloudKit` |
| Entitlement | `JournalInsight.entitlements` | `com.apple.developer.icloud-container-identifiers = ["iCloud.com.tobias.JournalInsight"]` |
| Entitlement | `JournalInsight.entitlements` | `aps-environment = development` (release: `production`) |
| CloudKit Schema | CloudKit Dashboard | First deploy via development zone, then "Deploy to Production" before App Store submission |

### Conflict resolution

SwiftData+CloudKit's default last-writer-wins. `bodyCipher` is one atomic blob, so partial-field merging is impossible on ciphertext. For `Goal`, last-writer-wins is also acceptable (single-author edit conflicts are rare).

### Sync status

Derived from `NSPersistentCloudKitContainer.eventChangedNotification`:

```swift
enum SyncStatus { case syncing, idle, paused(PauseReason), error(LocalizedError) }
enum PauseReason { case notSignedIntoiCloud, iCloudKeychainUnavailable, networkOffline }
```

`paused` and `error` cases must be visible to the user, otherwise they can be silently local-only and think they're synced. Surfaces:

- **Settings → iCloud Sync → Status row** (always visible).
- **Dashboard toolbar — small icon** (only when `paused` or `error`; hidden during `syncing`/`idle`).

**No in-app sync on/off toggle.** Sync is on when iCloud is enabled at the OS level. Disabling per-app sync is done by the user in Settings.app → Apple ID → iCloud → JournalInsight.

### Settings UI — final shape

```
Name                          [unchanged]
Wallpaper                     [unchanged + .complete protection on the file]

Privacy & Lock                ← NEW
  Lock when I leave the app   [Picker: Immediately / 1 min / 5 min / 15 min / 1 hour]
  Lock Now                    [Button]
  Footer: "Face ID or your device passcode unlocks your journal."

iCloud Sync                   ← REPLACES misleading copy from C-2
  Status: [icon + text]
  "Your entries are encrypted on this device. Apple sees only encrypted
   data on iCloud."
  Disclosure row: "Manage in Settings.app" → opens iOS Settings deep link

Back Up Outside iCloud        ← NEW
  "Your journal syncs via iCloud automatically. To save a copy somewhere
   else (Dropbox, Google Drive, ProtonDrive…), use Export below and save
   the file to that provider via the Files app."
  ⚠ "Exported files are NOT encrypted."

Export Data                   ← keep, with new warning callout
  Format: CSV / JSON
  Export N Entries             [Button]
  ⚠ "These exports are not encrypted. Anyone with the file can read it."

Daily Reminder                ← keep, audit H-7 fix folded in
  Toggle + state-sync with notificationSettings() on .onAppear

Accent Color                  [unchanged]
Text Size                     [unchanged]
Appearance                    [unchanged]

(About section: deferred — see "Pending v1.1 / open items" below)
```

### iOS hardening floor — non-negotiable

| Item | Where | Note |
|---|---|---|
| `.complete` file protection on SwiftData store | `JournalInsightApp` first-launch | Set `.protectionKey` on `default.store` before opening |
| `.complete` file protection on `wallpaper.dat` | `WallpaperStorage.save` | `try data.write(to:, options: [.atomic, .completeFileProtection])` |
| `.isExcludedFromBackup = true` on wallpaper + exports | Same writes | Resource value |
| `PrivacyInfo.xcprivacy` manifest | Project root, member of app target | Includes `UserDefaults` (CA92.1) + `FileTimestamp` (C617.1) reasons |
| App Store privacy labels | App Store Connect | "Other User Content" linked-to-user; tracking: No |
| `PrivacyOverlay` modifier | `JournalInsightApp` root view | Always-on; redacts on `scenePhase != .active` |
| Sync `notificationsEnabled` toggle with `notificationSettings()` | `SettingsView.onAppear` | Closes audit H-7 |
| CSV export sanitization (`= + - @ \t \r` prefix) | `DataExporter.exportCSV` | Closes audit S-9 |
| Export file cleanup on share-sheet dismiss | `ShareSheetView.onDisappear` | Closes audit S-6 |
| `os.Logger` with `privacy:` annotations | New code path | All logging routes through one helper that defaults `.private` |

---

## Section 6 — Error handling and testing strategy

### Error taxonomy

```swift
enum VaultError: Error, LocalizedError {
    case userCancelled                 // user dismissed biometric prompt
    case osBlocked                     // LAError.biometryLockout / passcodeNotSet
    case keychainUnavailable           // SecItemCopyMatching → errSecNotAvailable (rare)
    case iCloudKeychainUnavailable     // first-time launch on device with no master key + no iCloud Keychain
    case decryptionFailed              // GCM auth tag failure, AAD mismatch, malformed envelope
}

enum MigrationError: Error, LocalizedError {
    case schemaMigrationFailed(underlying: Error)       // Stage 1 — fatal
    case rowQuarantined(id: UUID, underlying: Error)    // single row; non-blocking
    case containerSwapFailed(underlying: Error)         // post-Stage-2 — fatal, diagnostic
    case interrupted                                    // mid-migration kill (informational)
}

enum SyncError: Error {                                 // mapped from NSPersistentCloudKitContainer
    case notSignedIntoiCloud
    case networkOffline
    case quotaExceeded
    case schemaMismatch                                 // CloudKit schema not deployed to production
    case unknown(NSError)
}
```

### Surfacing to the user

| Error | Surface | Recovery |
|---|---|---|
| `VaultError.userCancelled` | Inline "🔒 Tap to unlock" pill on the entry row | User taps → re-prompt biometric |
| `VaultError.osBlocked` | Banner: *"Face ID is temporarily disabled. Unlock your iPhone to retry."* | iOS handles |
| `VaultError.iCloudKeychainUnavailable` | Full-screen sheet on first launch with deep link to Settings.app | User enables iCloud Keychain → retry |
| `VaultError.decryptionFailed` (entry-level) | Row shows ⚠ "Unable to decrypt — entry may be corrupted." Tappable to view raw envelope hex (advanced) and a "Report" mailto. | None automatic |
| `MigrationError.schemaMigrationFailed` | Fatal alert; "Reinstall to recover." | CloudKit re-pull |
| `MigrationError.containerSwapFailed` | Fatal alert with diagnostic; logged to `os.Logger` for crash report | Manual support path |
| `SyncError.notSignedIntoiCloud` | Sync-status banner in Settings + toolbar icon | User signs in → auto-resumes |
| `SyncError.schemaMismatch` | Same surface, different copy: *"Sync is paused while we update."* | Apple's CloudKit Dashboard fix |

### Logging policy

All logging routes through one helper that defaults to `.private` for any interpolation:

```swift
extension Logger {
    static let vault     = Logger(subsystem: "com.tobias.JournalInsight", category: "vault")
    static let migration = Logger(subsystem: "com.tobias.JournalInsight", category: "migration")
    static let sync      = Logger(subsystem: "com.tobias.JournalInsight", category: "sync")
    static let crypto    = Logger(subsystem: "com.tobias.JournalInsight", category: "crypto")
    static let storage   = Logger(subsystem: "com.tobias.JournalInsight", category: "storage")
}

// Usage
Logger.vault.error("unlock failed: \(error.localizedDescription, privacy: .public) " +
                   "entry=\(entry.id, privacy: .private(mask: .hash))")
```

### Lint rules scoped to security-critical paths

| Rule | Scope | Failure |
|---|---|---|
| `no_try_question` | `Vault/`, `Storage/`, `Migration/` | `try?` is forbidden — must be `try` with explicit catch |
| `no_print_in_release` | All | `print()` warns; `Logger` enforced |
| `vault_log_privacy_required` | `Vault/`, `Repositories/`, `Storage/`, `Migration/` | Any `Logger.*` interpolation without explicit `privacy:` is a hard CI failure |
| `forbidden_apis_in_vault` | `Vault/` | No `UserDefaults`, no `UIPasteboard` |

### Testing strategy

#### Unit tests (extends current Swift Testing suite)

```
@Suite("EnvelopeCodec")
  - encode then decode produces same EntryBody
  - decode with wrong key throws .decryptionFailed
  - decode with tampered ciphertext throws .decryptionFailed
  - decode with mismatched AAD (entry id swap) throws .decryptionFailed
  - encoded envelope has correct version byte + nonce length
  - two encodes of same body produce different ciphertexts (nonce uniqueness)

@Suite("VaultManager")               // uses fake KeychainService
  - sealed → sessionKey → unlocking → unlocked
  - unlocked → idle timeout → sealed
  - unlocked → lockNow → sealed
  - unlocking → user cancel → sealed
  - unlocking → osBlocked → osBlocked
  - lock policy change mid-session takes effect on next background-entry

@Suite("LockPolicy")
  - all cases produce non-zero, distinct durations
  - default = .fiveMinutes

@Suite("MigrationCoordinator")
  - pendingCount on empty DB = 0
  - pendingCount counts only schemaVersion == 0
  - run() encrypts all pending and clears plaintext
  - run() is idempotent — second call after partial completion only does remaining
  - bad-row decode → schemaVersion = -1 (quarantine), other rows succeed

@Suite("StreakCalculator")           // existing + new
  + DST boundary test (audit H-1)
  + Circular-mean midnight-crossing test (audit H-2)

@Suite("DataExporter")               // existing + new
  + CSV sanitization for leading = + - @ \t \r (audit S-9)
```

#### Integration tests (new — require SwiftData in-memory + CloudKit mocks where possible)

- **Schema migration V0→V1**: seed in-memory store with V0 entities, run migration plan, assert columns present and defaults correct.
- **Container swap** *(release-blocker)*: build local-only container with v0 data → run Stage 2 → tear down → build CloudKit container against same SQLite file → fetch entries and assert all visible, decryptable, and at `schemaVersion == 1`.
- **Mid-migration kill recovery**: run Stage 2 for half the entries → tear down → reopen → assert remaining-pending count is correct, finish → assert all entries migrated.
- **Quarantine resilience**: seed one entry with corrupt source data + nine clean entries → run migration → assert nine succeed, one is quarantined.
- **Lock policy idle timer**: simulate `scenePhase` background→active with various elapsed times → assert state transitions.

#### UI tests (XCUITest)

- Cold launch (empty DB) → name prompt → dashboard.
- Cold launch (v0 data) → migration screen → mocked biometric success → dashboard with entries readable.
- Tap entry → entry text visible (vault unlocked from a previous step).
- Cold launch → tap entry → mocked biometric cancel → "Tap to unlock" pill visible.
- Settings → change lock policy from 5 min to 1 min → background → wait → return → verify re-prompt.
- Settings → Lock Now → verify entries show pills.
- Settings → Export → verify warning text rendered + share sheet opens.

#### Manual pre-release checklist

1. Two physical devices, same Apple ID, both signed into iCloud Keychain.
2. Install v1.0 on Device A → migrate → verify entries appear on Device B within ~30 s.
3. Edit entry on Device A → verify edit appears on Device B.
4. Sign Device B out of iCloud → install fresh on Device B → verify `iCloudKeychainUnavailable` sheet shown.
5. Disable iCloud → JournalInsight in OS Settings → verify sync-status icon shows "paused" in toolbar.
6. Set device clock back across DST → verify streak calc unaffected (validates audit H-1 in real device).
7. Migration with 10, 100, 1 000, 10 000 entries — measure wall-clock and verify no UI freeze.
8. CloudKit schema deployed to production via CloudKit Dashboard before TestFlight build.

---

## Pre-release security gate

Consolidated from the audit and v1.0-specific items. Every row must be green before App Store submission.

| # | Item | Status | Required |
|---|---|---|---|
| 1 | `.complete` file protection on SwiftData store | Open | Yes |
| 2 | `.complete` + `isExcludedFromBackup` on wallpaper | Open | Yes |
| 3 | `PrivacyInfo.xcprivacy` manifest with declared reasons | Open | Yes — App Store gate |
| 4 | App Store Connect privacy labels filled | Open | Yes — App Store gate |
| 5 | Privacy policy URL hosted and reachable | Open | Yes — App Store gate |
| 6 | App-switcher privacy overlay on `scenePhase != .active` | Open | Yes |
| 7 | CloudKit container created + schema deployed to **production** | Open | Yes |
| 8 | Container-swap integration test passes | Pending | Yes |
| 9 | Migration idempotency integration test passes | Pending | Yes |
| 10 | EnvelopeCodec AAD-tampering test passes | Pending | Yes |
| 11 | Lint rule `vault_log_privacy_required` enforced in CI | Pending | Yes |
| 12 | CSV export sanitization (audit S-9) | Open | Recommended |
| 13 | Export-file cleanup on share-sheet dismiss (audit S-6) | Open | Recommended |
| 14 | Sync `notificationsEnabled` toggle with `notificationSettings()` (H-7) | Open | Recommended |
| 15 | DST-safe streak test (H-1) + midnight circular-mean test (H-2) | Open | Recommended |

---

## Pending v1.1 / open items

Documented now so they're not lost:

- **Schema cleanup migration** (Stage 3): drop `text`, `moodRaw`, and the `Tag` model entirely.
- **About section in Settings**: with version, build, and link to privacy-policy URL.
- **Optional encrypted export format** (passphrase-derived AES key, portable across providers).
- **Per-entry sharing** with separate keys (e.g. share a single entry with a therapist).
- **iPadOS-specific layouts / macOS Catalyst surface**.
- **User-passphrase "Paranoid Mode"** (true zero-knowledge against Apple). Considered and rejected for v1; revisit if user research surfaces demand.

---

## Glossary

| Term | Definition |
|---|---|
| **AAD** | Additional Authenticated Data — bytes mixed into AES-GCM authentication but not into ciphertext. Used here as `entry.id || schemaVersion` so ciphertext re-association is detectable. |
| **Container swap** | The technique of building one `ModelContainer` with `cloudKitDatabase: .none` for migration, tearing it down, then building another with `.private(...)` for the running app. |
| **Quarantine** | A row whose plaintext could not be encrypted during Stage 2. Marked `schemaVersion = -1`. Visible to the user via a banner; not blocking. |
| **iCloud Keychain HSM escrow** | Apple's mechanism that lets a user recover iCloud Keychain on a new device after entering their device passcode. Provides our recovery story under decision #3. |
| **Plaintext metadata** | `JournalEntry.date` and `duration`. Visible to CloudKit and on-device tooling. Per decision #4. |

---

*End of design.*
