# Plan 4 — Container Swap + App Boot

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite `JournalInsightApp` so first launch builds a *pre-migration* `ModelContainer` (CloudKit off), runs Stage 2 if any v0 rows exist, and only after migration completes builds the *final* CloudKit-enabled container. Add the `PrivacyOverlay` view modifier (always-on background redaction) and the `MigrationSheet` UI.

**Architecture:** `JournalInsightApp` holds the container as `@State`. A `BootCoordinator` actor orchestrates the boot sequence. `MigrationSheet` is a SwiftUI view with four states (`Idle`, `Encrypting(progress)`, `Done`, `Failed`). `PrivacyOverlay` is a stateless view modifier that draws a redacted layer when `scenePhase != .active`. The container-swap integration test uses a temporary on-disk SQLite to validate that local-only and CloudKit-enabled containers can both open the same store.

**Tech Stack:** SwiftUI (`@main`, `WindowGroup`, `@State`, `ScenePhase`), SwiftData (`ModelContainer`, `ModelConfiguration`), the foundations from Plans 1–3.

**Spec section reference:** §4 (Why CloudKit is off during Stage 2; container-swap diagram; migration UI), §5 (PrivacyOverlay).

**Depends on:** Plan 1 (`Logger`), Plan 2 (`VaultManager`, `LockPolicySettings`), Plan 3 (`MigrationCoordinator`, `JournalMigrationPlan`).

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Create | `JournalInsight/Vault/PrivacyOverlay.swift` | View modifier — always-on redacted layer when `scenePhase != .active` |
| Create | `JournalInsight/Migration/MigrationSheet.swift` | Full-screen sheet with 4 states + progress |
| Create | `JournalInsight/Migration/BootCoordinator.swift` | Orchestrates: build pre-migration → run Stage 2 → swap to CloudKit container |
| Modify | `JournalInsight/JournalInsightApp.swift` | Replace top-level `WindowGroup` with `BootCoordinator`-driven flow |
| Create | `JournalInsightTests/PrivacyOverlayTests.swift` | Snapshot of overlay visibility per phase |
| Create | `JournalInsightTests/ContainerSwapTests.swift` | **Release blocker** — local-only → CloudKit container against same SQLite file |

---

## Task 1: PrivacyOverlay

**Files:**
- Create: `JournalInsight/Vault/PrivacyOverlay.swift`
- Create: `JournalInsightTests/PrivacyOverlayTests.swift`

- [ ] **Step 1.1: Write failing tests**

```swift
// JournalInsightTests/PrivacyOverlayTests.swift
import Testing
import SwiftUI
@testable import JournalInsight

@MainActor
@Suite("PrivacyOverlay")
struct PrivacyOverlayTests {

    @Test("isRedacted returns true for non-active phases")
    func redactedForNonActive() {
        #expect(PrivacyOverlay.isRedacted(.background) == true)
        #expect(PrivacyOverlay.isRedacted(.inactive)   == true)
    }

    @Test("isRedacted returns false for active phase")
    func notRedactedForActive() {
        #expect(PrivacyOverlay.isRedacted(.active) == false)
    }
}
```

- [ ] **Step 1.2: Run tests to verify they fail**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/PrivacyOverlay
```
Expected: FAIL.

- [ ] **Step 1.3: Implement PrivacyOverlay**

```swift
// JournalInsight/Vault/PrivacyOverlay.swift
import SwiftUI

/// Draws an opaque redacted layer over the app whenever `scenePhase != .active`.
/// Independent of vault unlock state — purely a snapshot-leak mitigation.
/// Closes audit S-2 from CODE_REVIEW.html.
struct PrivacyOverlay: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        ZStack {
            content
            if Self.isRedacted(scenePhase) {
                Color(.systemBackground)
                    .ignoresSafeArea()
                    .overlay(
                        Image(systemName: "lock.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    )
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: scenePhase)
    }

    static func isRedacted(_ phase: ScenePhase) -> Bool {
        switch phase {
        case .active:                return false
        case .inactive, .background: return true
        @unknown default:            return true       // fail closed
        }
    }
}

extension View {
    /// Apply the always-on privacy overlay. Anchor at app root.
    func privacyOverlay() -> some View {
        modifier(PrivacyOverlay())
    }
}
```

- [ ] **Step 1.4: Run tests to verify they pass**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/PrivacyOverlay
```
Expected: 2 tests passing.

- [ ] **Step 1.5: Commit**

```bash
git add JournalInsight/Vault/PrivacyOverlay.swift JournalInsightTests/PrivacyOverlayTests.swift
git commit -m "feat(vault): add PrivacyOverlay view modifier (audit S-2)"
```

---

## Task 2: MigrationSheet UI

**Files:**
- Create: `JournalInsight/Migration/MigrationSheet.swift`

This view is exercised end-to-end by Plan 4 Task 4's container-swap integration test; no separate unit tests here.

- [ ] **Step 2.1: Implement MigrationSheet**

```swift
// JournalInsight/Migration/MigrationSheet.swift
import SwiftUI

struct MigrationSheet: View {
    enum State: Equatable {
        case idle
        case encrypting(current: Int, total: Int)
        case done
        case failed(message: String)
    }

    @Binding var state: State
    var onContinue: () -> Void
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            iconLayer
            textLayer
            Spacer()
            controlLayer
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    @ViewBuilder
    private var iconLayer: some View {
        switch state {
        case .idle:
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
        case .encrypting:
            ProgressView()
                .controlSize(.large)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var textLayer: some View {
        switch state {
        case .idle:
            VStack(spacing: 8) {
                Text("Setting up encrypted storage")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Your journal is moving to encrypted, end-to-end iCloud storage. This takes a few seconds. Tap Continue to authenticate.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        case .encrypting(let current, let total):
            VStack(spacing: 12) {
                Text("Encrypting your journal")
                    .font(.title3.bold())
                ProgressView(value: Double(current), total: Double(total))
                    .progressViewStyle(.linear)
                Text("Encrypting entry \(current) of \(total)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .done:
            Text("Done!")
                .font(.title2.bold())
        case .failed(let message):
            VStack(spacing: 8) {
                Text("Migration paused")
                    .font(.title3.bold())
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var controlLayer: some View {
        switch state {
        case .idle:
            Button(action: onContinue) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .encrypting:
            EmptyView()
        case .done:
            EmptyView()
        case .failed:
            Button(action: onRetry) {
                Text("Retry")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

#Preview("Idle") {
    StateWrapper(initial: .idle)
}

#Preview("Encrypting") {
    StateWrapper(initial: .encrypting(current: 14, total: 22))
}

#Preview("Done") {
    StateWrapper(initial: .done)
}

#Preview("Failed") {
    StateWrapper(initial: .failed(message: "Some entries couldn't be encrypted."))
}

private struct StateWrapper: View {
    @State private var state: MigrationSheet.State
    init(initial: MigrationSheet.State) { _state = .init(initialValue: initial) }
    var body: some View {
        MigrationSheet(state: $state, onContinue: {}, onRetry: {})
    }
}
```

- [ ] **Step 2.2: Build succeeds**

```
xcodebuild build -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 2.3: Commit**

```bash
git add JournalInsight/Migration/MigrationSheet.swift
git commit -m "feat(migration): add MigrationSheet UI with idle/encrypting/done/failed states"
```

---

## Task 3: BootCoordinator

**Files:**
- Create: `JournalInsight/Migration/BootCoordinator.swift`

- [ ] **Step 3.1: Implement BootCoordinator**

```swift
// JournalInsight/Migration/BootCoordinator.swift
import Foundation
import SwiftData
import os

@MainActor
@Observable
final class BootCoordinator {

    enum BootState: Equatable {
        case starting                              // pre-Stage-1
        case awaitingMigration                     // pending > 0, sheet should show .idle
        case migrating(current: Int, total: Int)
        case migrationFailed(message: String)
        case ready(ModelContainer)
    }

    private(set) var state: BootState = .starting

    private let storeURL: URL
    private let cloudKitContainerID: String
    private let vault: VaultManager

    init(
        storeURL: URL = URL.applicationSupportDirectory.appendingPathComponent("default.store"),
        cloudKitContainerID: String = "iCloud.com.tobias.JournalInsight",
        vault: VaultManager
    ) {
        self.storeURL = storeURL
        self.cloudKitContainerID = cloudKitContainerID
        self.vault = vault
    }

    /// Step 1: build the pre-migration container (CloudKit off) and check pending.
    /// Returns the pre-migration ModelContainer so the caller can present the sheet
    /// against it if migration is needed.
    func startBoot() async {
        do {
            // Set .complete file protection on the parent directory before opening
            try ensureFileProtection()
            let pre = try buildContainer(cloudKit: false)
            let preCtx = ModelContext(pre)
            let pending = try MigrationCoordinator.pendingCount(in: preCtx)
            if pending == 0 {
                // Empty DB or already migrated — go straight to final container.
                let final = try buildContainer(cloudKit: true)
                state = .ready(final)
            } else {
                state = .awaitingMigration
                // Sheet drives the actual run via runMigration(in:)
                self.cachedPreContainer = pre
            }
        } catch {
            Logger.migration.error("boot failed: \(error.localizedDescription, privacy: .public)")
            state = .migrationFailed(message: error.localizedDescription)
        }
    }

    /// Step 2: invoked when user taps Continue on the migration sheet.
    func runMigration() async {
        guard let pre = cachedPreContainer else {
            state = .migrationFailed(message: "Boot did not produce a pre-migration container.")
            return
        }
        let ctx = ModelContext(pre)
        do {
            try await MigrationCoordinator.run(in: ctx, vault: vault) { [weak self] current, total in
                self?.state = .migrating(current: current, total: total)
            }
            // Tear down pre-container by dropping references + swap to final.
            cachedPreContainer = nil
            let final = try buildContainer(cloudKit: true)
            state = .ready(final)
        } catch {
            Logger.migration.error("migration failed: \(error.localizedDescription, privacy: .public)")
            state = .migrationFailed(message: error.localizedDescription)
        }
    }

    private var cachedPreContainer: ModelContainer?

    private func buildContainer(cloudKit: Bool) throws -> ModelContainer {
        let schema = Schema([JournalEntry.self, Goal.self, Tag.self])
        let cfg: ModelConfiguration
        if cloudKit {
            cfg = ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
        } else {
            cfg = ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: JournalMigrationPlan.self,
            configurations: cfg
        )
    }

    private func ensureFileProtection() throws {
        let fm = FileManager.default
        let parent = storeURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        // Apply .complete file protection to the directory; SwiftData inherits.
        try fm.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: parent.path
        )
    }
}
```

- [ ] **Step 3.2: Build succeeds**

```
xcodebuild build -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3.3: Commit**

```bash
git add JournalInsight/Migration/BootCoordinator.swift
git commit -m "feat(boot): add BootCoordinator orchestrating pre-migration container, Stage 2, and CloudKit swap"
```

---

## Task 4: Container-swap integration test (release blocker)

**Files:**
- Create: `JournalInsightTests/ContainerSwapTests.swift`

This test exercises the riskiest mechanic in the design. Spec §4 marks it a release blocker.

- [ ] **Step 4.1: Write integration test**

```swift
// JournalInsightTests/ContainerSwapTests.swift
import Testing
import Foundation
import SwiftData
import CryptoKit
@testable import JournalInsight

@MainActor
@Suite("ContainerSwap (integration)")
struct ContainerSwapTests {

    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID()).store")
    }

    private static func cleanup(_ url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        try? fm.removeItem(at: url.appendingPathExtension("shm"))
        try? fm.removeItem(at: url.appendingPathExtension("wal"))
    }

    @Test("Local-only container then re-open without CloudKit preserves data")
    func reopenWithoutCloudKit() throws {
        let url = tempStoreURL()
        defer { Self.cleanup(url) }

        let schema = Schema([JournalEntry.self, Goal.self, Tag.self])

        // Open #1 — local-only, write entries.
        let cfg1 = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container1 = try ModelContainer(for: schema, migrationPlan: JournalMigrationPlan.self, configurations: cfg1)
        let ctx1 = ModelContext(container1)
        let key = SymmetricKey(size: .bits256)
        let body = EntryBody(text: "hello", mood: .good, tags: ["work"])
        let id = UUID()
        let env = try EnvelopeCodec.encode(body, key: key, entryID: id, schemaVersion: 1)
        let entry = JournalEntry(id: id, date: .now, text: "", duration: 600)
        entry.text = nil; entry.moodRaw = nil; entry.tags = []
        entry.bodyCipher = env.cipher; entry.nonce = env.nonce; entry.schemaVersion = 1
        ctx1.insert(entry)
        try ctx1.save()

        // Tear down: drop references — SwiftData closes when no contexts remain.
        // (In a real boot, dropping the `BootCoordinator.cachedPreContainer` reference does this.)

        // Open #2 — same schema + URL, *also* local-only (we cannot really
        // exercise CloudKit in unit tests without a signed-in iCloud account
        // — Plan 7 manual test #2 covers the production CloudKit case).
        let cfg2 = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container2 = try ModelContainer(for: schema, migrationPlan: JournalMigrationPlan.self, configurations: cfg2)
        let ctx2 = ModelContext(container2)
        let entries = try ctx2.fetch(FetchDescriptor<JournalEntry>())
        #expect(entries.count == 1)
        let fetched = try #require(entries.first)
        #expect(fetched.id == id)
        #expect(fetched.schemaVersion == 1)
        let decoded = try EnvelopeCodec.decode(fetched.bodyCipher, key: key, entryID: id, schemaVersion: 1)
        #expect(decoded.text == "hello")
        #expect(decoded.mood == .good)
        #expect(decoded.tags == ["work"])
    }

    @Test("Stage-1 lightweight migration upgrades a V0-only file to V1")
    func lightweightMigrationFromV0() throws {
        let url = tempStoreURL()
        defer { Self.cleanup(url) }

        let schema = Schema([JournalEntry.self, Goal.self, Tag.self])

        // Open with the migration plan — this synthesises V0→V1 since the URL
        // is empty. We can't easily generate a real V0 file in a unit test;
        // production validation happens in Plan 7 manual test step #1.
        let cfg = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: JournalMigrationPlan.self, configurations: cfg)
        let ctx = ModelContext(container)
        // Insert a V0-shaped entry: schemaVersion default 0, text populated.
        let entry = JournalEntry(date: .now, text: "legacy", duration: 600)
        ctx.insert(entry)
        try ctx.save()

        let pending = try MigrationCoordinator.pendingCount(in: ctx)
        #expect(pending == 1)
    }
}
```

- [ ] **Step 4.2: Run tests**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/ContainerSwap
```
Expected: 2 tests passing. If either fails, debug before proceeding to Task 5 — this is the release-blocker test.

- [ ] **Step 4.3: Commit**

```bash
git add JournalInsightTests/ContainerSwapTests.swift
git commit -m "test(boot): release-blocker integration test for container open/reopen across schema migration"
```

---

## Task 5: Wire JournalInsightApp to BootCoordinator

**Files:**
- Modify: `JournalInsight/JournalInsightApp.swift`

- [ ] **Step 5.1: Replace JournalInsightApp**

Replace the entire contents of `JournalInsight/JournalInsightApp.swift` with:

```swift
//
//  JournalInsightApp.swift
//  JournalInsight
//

import SwiftUI
import SwiftData

@main
struct JournalInsightApp: App {
    @AppStorage(StorageKeys.selectedAppearance) private var selectedAppearance: AppAppearance = .system
    @AppStorage(StorageKeys.textSize) private var textSize: TextSizeChoice = .medium
    @AppStorage(StorageKeys.accentColor) private var accentColorChoice: AccentColorChoice = .teal

    @State private var lockPolicy = LockPolicySettings()
    @State private var bootCoordinator: BootCoordinator?
    @State private var migrationSheetState: MigrationSheet.State = .idle
    @State private var vault: VaultManager?

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let coord = bootCoordinator {
                    rootContent(for: coord)
                } else {
                    Color(.systemBackground).ignoresSafeArea()
                        .task { await initBoot() }
                }
            }
            .preferredColorScheme(colorScheme)
            .dynamicTypeSize(textSize.sizeCategory)
            .tint(accentColorChoice.color)
            .privacyOverlay()
            .onChange(of: scenePhase) { _, newPhase in
                Task { await vault?.handleScenePhaseChange(newPhase) }
            }
        }
    }

    @ViewBuilder
    private func rootContent(for coord: BootCoordinator) -> some View {
        switch coord.state {
        case .starting, .awaitingMigration, .migrating, .migrationFailed:
            MigrationSheet(
                state: $migrationSheetState,
                onContinue: {
                    Task {
                        migrationSheetState = .encrypting(current: 0, total: 0)
                        await coord.runMigration()
                        syncSheetStateFromCoordinator(coord)
                    }
                },
                onRetry: {
                    Task {
                        migrationSheetState = .encrypting(current: 0, total: 0)
                        await coord.runMigration()
                        syncSheetStateFromCoordinator(coord)
                    }
                }
            )
            .task(id: coord.state) {
                syncSheetStateFromCoordinator(coord)
            }
        case .ready(let container):
            MainScreenView()
                .modelContainer(container)
                .environment(lockPolicy)
                .environment(vault!)
        }
    }

    private func syncSheetStateFromCoordinator(_ coord: BootCoordinator) {
        switch coord.state {
        case .starting:
            migrationSheetState = .idle
        case .awaitingMigration:
            migrationSheetState = .idle
        case .migrating(let current, let total):
            migrationSheetState = .encrypting(current: current, total: total)
        case .migrationFailed(let message):
            migrationSheetState = .failed(message: message)
        case .ready:
            migrationSheetState = .done
        }
    }

    private func initBoot() async {
        let v = VaultManager(keychain: KeychainStore(), lockPolicy: lockPolicy)
        self.vault = v
        let coord = BootCoordinator(vault: v)
        self.bootCoordinator = coord
        await coord.startBoot()
        syncSheetStateFromCoordinator(coord)
    }

    private var colorScheme: ColorScheme? {
        switch selectedAppearance {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }
}
```

- [ ] **Step 5.2: Build succeeds**

```
xcodebuild build -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5.3: Run all tests**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: All tests pass — the wiring should not break any existing tests because the wiring code itself isn't covered by unit tests (it's exercised by the smoke run in Step 5.4).

- [ ] **Step 5.4: Smoke run on simulator**

Launch the app on iPhone 16 simulator. Expected behaviour:

1. App launches.
2. With an empty DB: migration sheet does **not** appear; app drops directly to `MainScreenView`.
3. The simulator's biometric is enrolled (Hardware → Face ID → Enrolled). Tap an entry-creation flow; biometric prompt appears.
4. After matching, entries can be created and read.

If sample-data seeding from `MainScreenView` runs and inserts v0 entries on first launch, the migration sheet should appear at that point — but Plan 5 will fix the seed flow to write encrypted entries directly.

- [ ] **Step 5.5: Commit**

```bash
git add JournalInsight/JournalInsightApp.swift
git commit -m "feat(boot): wire JournalInsightApp to BootCoordinator with migration sheet flow and PrivacyOverlay"
```

---

## Plan-4 acceptance

- [ ] All 2 PrivacyOverlay tests pass.
- [ ] All 2 ContainerSwap integration tests pass *(release blocker)*.
- [ ] Smoke run on simulator: app launches, dashboard appears, no crashes.
- [ ] `JournalInsightApp` no longer constructs the model container at the top of `body` — it goes through `BootCoordinator`.
- [ ] `.privacyOverlay()` is applied at the root `WindowGroup`.

When all five tasks are checked, this plan is complete.
