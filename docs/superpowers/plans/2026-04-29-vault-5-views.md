# Plan 5 — Repository + View Rewiring

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `EntryRepository`, the `@MainActor` SwiftUI surface that decrypts entries on demand. Rewire every view that reads `JournalEntry.text` / `mood` / `tags` to fetch through the repository. Add the **"🔒 Tap to unlock"** pill UX for `VaultError.userCancelled`. Keep date/duration metadata-only widgets (streak, calendar dots, "this week" count) working without unlock. Fix the audit DST + circular-mean issues in `StreakCalculator` along the way.

**Architecture:** `EntryRepository` is a small `@MainActor` struct that takes a `VaultManager`. Views inject it via `@Environment` (set by `JournalInsightApp` from Plan 4). Each view that displays text wraps the row in an `EntryUnlockGate` view that handles the three states: locked (show pill), unlocking (show progress), unlocked (show body). The repository surfaces a tiny in-memory cache keyed by `entry.persistentModelID` and invalidated on vault lock.

**Tech Stack:** SwiftUI, SwiftData (`@Query`, `@Bindable`), Swift Concurrency (`Task`, `await`), Plans 1–3 foundations.

**Spec section reference:** §1 (`EntryRepository`, plaintext lifetime), §3 (Inline "Tap to unlock" pill), Audit H-1, H-2.

**Depends on:** Plan 1 (`EntryBody`, `EnvelopeCodec`), Plan 2 (`VaultManager`), Plan 3 (schema with `bodyCipher`/`nonce`/`schemaVersion` columns).

**Does NOT depend on Plan 4 to write or test** — uses in-memory `ModelContainer` for tests; runtime integration covered by Plan 4's smoke test.

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Create | `JournalInsight/Repositories/EntryRepository.swift` | `body(for:) async throws -> EntryBody`, `save(text:mood:tags:to:)`, `invalidateAll()`, in-memory cache |
| Create | `JournalInsight/Vault/EntryUnlockGate.swift` | View wrapper showing pill / spinner / decrypted content |
| Modify | `JournalInsight/MainScreenView.swift` | `EntryRowView` → use `EntryUnlockGate`; `AddEntrySheet` / `EditEntrySheet` save through repo; remove `Tag` SwiftData usage; sample seed writes encrypted |
| Modify | `JournalInsight/CalendarDetailView.swift` | Day-cells use plaintext date+mood-emoji-from-decrypted; lazy decryption only on tap |
| Modify | `JournalInsight/SessionDetailView.swift` | Metadata charts (count, duration) work locked; mood chart guarded by unlock |
| Modify | `JournalInsight/StreakDetailView.swift` | Use repo for `total entries` count (date metadata is plaintext) |
| Modify | `JournalInsight/StreakCalculator.swift` | DST-safe `bestStreak`; circular-mean `preferredTimeOfDay` |
| Modify | `JournalInsight/QuestionsDetailView.swift` | Save responses via repo |
| Create | `JournalInsightTests/EntryRepositoryTests.swift` | Body decode/encode round trip, cache, invalidation |
| Modify | `JournalInsightTests/JournalInsightTests.swift` | Add DST + circular-mean tests for `StreakCalculator` |

---

## Task 1: EntryRepository

**Files:**
- Create: `JournalInsight/Repositories/EntryRepository.swift`
- Create: `JournalInsightTests/EntryRepositoryTests.swift`

- [ ] **Step 1.1: Write failing tests**

```swift
// JournalInsightTests/EntryRepositoryTests.swift
import Testing
import Foundation
import SwiftData
import CryptoKit
@testable import JournalInsight

@MainActor
@Suite("EntryRepository")
struct EntryRepositoryTests {

    private func makeContext() throws -> ModelContext {
        let cfg = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: JournalEntry.self, Goal.self, Tag.self,
            configurations: cfg
        )
        return ModelContext(container)
    }

    private func makeVault(_ key: SymmetricKey) -> VaultManager {
        let fake = FakeKeychain(); fake.seedKey(key)
        let suite = UserDefaults(suiteName: "test.repo.\(UUID())")!
        return VaultManager(keychain: fake, lockPolicy: LockPolicySettings(suite: suite))
    }

    @Test("save encrypts and body decrypts back")
    func roundTripSaveBody() async throws {
        let ctx = try makeContext()
        let key = SymmetricKey(size: .bits256)
        let vault = makeVault(key)
        let repo = EntryRepository(context: ctx, vault: vault)

        let entry = try await repo.create(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 600,
            text: "hello",
            mood: .good,
            tags: ["one"]
        )

        #expect(entry.schemaVersion == 1)
        #expect(entry.bodyCipher.isEmpty == false)
        #expect(entry.text == nil)

        let body = try await repo.body(for: entry)
        #expect(body.text == "hello")
        #expect(body.mood == .good)
        #expect(body.tags == ["one"])
    }

    @Test("body cache returns same value without re-decrypting")
    func cachedBody() async throws {
        let ctx = try makeContext()
        let vault = makeVault(SymmetricKey(size: .bits256))
        let repo = EntryRepository(context: ctx, vault: vault)
        let entry = try await repo.create(date: .now, duration: 600, text: "x", mood: nil, tags: [])

        let first = try await repo.body(for: entry)
        let second = try await repo.body(for: entry)
        #expect(first == second)                     // identical content
        // No way to assert "no decrypt happened" without a counter — covered by inspection.
    }

    @Test("invalidateAll forces re-decryption")
    func invalidateForcesReDecrypt() async throws {
        let ctx = try makeContext()
        let vault = makeVault(SymmetricKey(size: .bits256))
        let repo = EntryRepository(context: ctx, vault: vault)
        let entry = try await repo.create(date: .now, duration: 600, text: "x", mood: nil, tags: [])

        _ = try await repo.body(for: entry)
        await repo.invalidateAll()
        // Subsequent call should still succeed
        let body = try await repo.body(for: entry)
        #expect(body.text == "x")
    }

    @Test("update encrypts new text and clears cache for that entry")
    func updateClearsCache() async throws {
        let ctx = try makeContext()
        let vault = makeVault(SymmetricKey(size: .bits256))
        let repo = EntryRepository(context: ctx, vault: vault)
        let entry = try await repo.create(date: .now, duration: 600, text: "before", mood: nil, tags: [])
        _ = try await repo.body(for: entry)
        try await repo.update(entry, text: "after", mood: .great, tags: ["t"])
        let body = try await repo.body(for: entry)
        #expect(body.text == "after")
        #expect(body.mood == .great)
        #expect(body.tags == ["t"])
    }

    @Test("body throws .userCancelled when vault rejects")
    func bodyThrowsOnVaultCancel() async throws {
        let ctx = try makeContext()
        let key = SymmetricKey(size: .bits256)
        let vaultGood = makeVault(key)
        let repoCreate = EntryRepository(context: ctx, vault: vaultGood)
        let entry = try await repoCreate.create(date: .now, duration: 600, text: "x", mood: nil, tags: [])

        // Now hand the entry to a repo whose vault refuses
        let fake2 = FakeKeychain(); fake2.loadError = .userCancelled
        let suite2 = UserDefaults(suiteName: "test.repo.\(UUID())")!
        let vaultBad = VaultManager(keychain: fake2, lockPolicy: LockPolicySettings(suite: suite2))
        let repoRead = EntryRepository(context: ctx, vault: vaultBad)
        await #expect(throws: VaultError.userCancelled) {
            _ = try await repoRead.body(for: entry)
        }
    }
}
```

- [ ] **Step 1.2: Run tests to verify they fail**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/EntryRepository
```
Expected: FAIL.

- [ ] **Step 1.3: Implement EntryRepository**

```swift
// JournalInsight/Repositories/EntryRepository.swift
import Foundation
import SwiftData
import CryptoKit
import os

@MainActor
struct EntryRepository {
    private let context: ModelContext
    private let vault: VaultManager

    init(context: ModelContext, vault: VaultManager) {
        self.context = context
        self.vault = vault
    }

    /// Decrypt-and-return cached body for an entry. Throws `VaultError` if
    /// the user cancels biometric or the vault is osBlocked.
    func body(for entry: JournalEntry) async throws -> EntryBody {
        if let cached = Cache.shared.body(for: entry.persistentModelID) {
            return cached
        }
        let key = try await vault.sessionKey()
        do {
            let body = try EnvelopeCodec.decode(
                entry.bodyCipher,
                key: key,
                entryID: entry.id,
                schemaVersion: entry.schemaVersion
            )
            Cache.shared.set(body, for: entry.persistentModelID)
            return body
        } catch {
            Logger.crypto.error("decrypt entry=\(entry.id, privacy: .private(mask: .hash)) failed: \(error.localizedDescription, privacy: .public)")
            throw VaultError.decryptionFailed
        }
    }

    /// Create a new encrypted entry. Returns the inserted, saved JournalEntry.
    @discardableResult
    func create(
        date: Date,
        duration: TimeInterval,
        text: String,
        mood: Mood?,
        tags: [String]
    ) async throws -> JournalEntry {
        let key = try await vault.sessionKey()
        let entry = JournalEntry(date: date, text: "", duration: duration)
        entry.text = nil
        entry.moodRaw = nil
        entry.tags = []
        let body = EntryBody(text: text, mood: mood, tags: tags)
        let env = try EnvelopeCodec.encode(body, key: key, entryID: entry.id, schemaVersion: 1)
        entry.bodyCipher = env.cipher
        entry.nonce = env.nonce
        entry.schemaVersion = 1
        context.insert(entry)
        try context.save()
        Cache.shared.set(body, for: entry.persistentModelID)
        return entry
    }

    /// Update an existing entry's encrypted body.
    func update(
        _ entry: JournalEntry,
        text: String,
        mood: Mood?,
        tags: [String]
    ) async throws {
        let key = try await vault.sessionKey()
        let body = EntryBody(text: text, mood: mood, tags: tags)
        let env = try EnvelopeCodec.encode(body, key: key, entryID: entry.id, schemaVersion: 1)
        entry.bodyCipher = env.cipher
        entry.nonce = env.nonce
        entry.schemaVersion = 1
        try context.save()
        Cache.shared.set(body, for: entry.persistentModelID)
    }

    func delete(_ entry: JournalEntry) throws {
        Cache.shared.invalidate(entry.persistentModelID)
        context.delete(entry)
        try context.save()
    }

    /// Drop all cached plaintext. Called on vault lock events.
    func invalidateAll() async {
        Cache.shared.clear()
    }

    // MARK: - Cache (process-memory only, MainActor)

    @MainActor
    final class Cache {
        static let shared = Cache()
        private init() {}
        private var storage: [PersistentIdentifier: EntryBody] = [:]

        func body(for id: PersistentIdentifier) -> EntryBody? { storage[id] }
        func set(_ body: EntryBody, for id: PersistentIdentifier) { storage[id] = body }
        func invalidate(_ id: PersistentIdentifier) { storage.removeValue(forKey: id) }
        func clear() { storage.removeAll() }
    }
}
```

- [ ] **Step 1.4: Run tests to verify they pass**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/EntryRepository
```
Expected: 5 tests passing.

- [ ] **Step 1.5: Commit**

```bash
git add JournalInsight/Repositories/EntryRepository.swift JournalInsightTests/EntryRepositoryTests.swift
git commit -m "feat(repo): add EntryRepository with create/update/body/delete and process-memory cache"
```

---

## Task 2: EntryUnlockGate UI

**Files:**
- Create: `JournalInsight/Vault/EntryUnlockGate.swift`

- [ ] **Step 2.1: Implement EntryUnlockGate**

```swift
// JournalInsight/Vault/EntryUnlockGate.swift
import SwiftUI
import SwiftData

/// Wraps any view that needs to display decrypted entry content.
///
/// States:
///   - `.locked`        — vault sealed, show "🔒 Tap to unlock" pill
///   - `.unlocking`     — biometric prompt in flight, show progress
///   - `.unlocked(body)` — render `content(body)`
///   - `.failed`        — show ⚠ pill
///
/// Tapping the locked pill triggers `await repo.body(for:)`, which kicks
/// the biometric prompt. On success the gate flips to `.unlocked`.
struct EntryUnlockGate<Content: View>: View {
    let entry: JournalEntry
    let repo: EntryRepository
    @ViewBuilder var content: (EntryBody) -> Content

    @State private var phase: Phase = .idle

    enum Phase: Equatable {
        case idle
        case unlocking
        case unlocked(EntryBody)
        case failed(message: String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.unlocking, .unlocking): return true
            case (.unlocked(let a), .unlocked(let b)): return a == b
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    var body: some View {
        Group {
            switch phase {
            case .idle:
                lockedPill
                    .task { await tryUnlock() }
            case .unlocking:
                ProgressView()
                    .controlSize(.small)
            case .unlocked(let body):
                content(body)
            case .failed:
                failedPill
            }
        }
    }

    private var lockedPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
            Text("Tap to unlock")
                .font(.caption)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
        .onTapGesture { Task { await tryUnlock(force: true) } }
    }

    private var failedPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Couldn't unlock")
                .font(.caption)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
        .onTapGesture { Task { await tryUnlock(force: true) } }
    }

    private func tryUnlock(force: Bool = false) async {
        if case .unlocked = phase, !force { return }
        phase = .unlocking
        do {
            let body = try await repo.body(for: entry)
            phase = .unlocked(body)
        } catch VaultError.userCancelled {
            phase = .idle                                  // back to pill
        } catch {
            phase = .failed(message: (error as? LocalizedError)?.errorDescription ?? "Unknown")
        }
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
git add JournalInsight/Vault/EntryUnlockGate.swift
git commit -m "feat(vault): add EntryUnlockGate with locked/unlocking/unlocked/failed phases"
```

---

## Task 3: Rewire EntryRowView in MainScreenView

**Files:**
- Modify: `JournalInsight/MainScreenView.swift`

- [ ] **Step 3.1: Read current EntryRowView and AddEntrySheet to understand**

Open `JournalInsight/MainScreenView.swift`. Find `EntryRowView` (around line 274) and `AddEntrySheet` (around line 405).

- [ ] **Step 3.2: Update top-level imports + injected environment**

At the top of the file (after `import SwiftData`), the file already has the imports needed. We will inject `EntryRepository` via environment in the rendering hierarchy. To make `EntryRepository` injectable, add an `EnvironmentKey`:

Append near the bottom of the file:

```swift
private struct EntryRepositoryKey: EnvironmentKey {
    static let defaultValue: EntryRepository? = nil
}
extension EnvironmentValues {
    var entryRepository: EntryRepository? {
        get { self[EntryRepositoryKey.self] }
        set { self[EntryRepositoryKey.self] = newValue }
    }
}
```

- [ ] **Step 3.3: Rewrite EntryRowView**

Replace the entire `struct EntryRowView` with:

```swift
struct EntryRowView: View {
    let entry: JournalEntry
    var onEdit: () -> Void
    var onDelete: () -> Void
    @State private var showDeleteConfirm = false
    @Environment(\.entryRepository) private var repo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(entry.duration) / 60) min")
                    .font(.caption2)
                    .foregroundColor(AppTheme.primaryColor)
            }
            if let repo {
                EntryUnlockGate(entry: entry, repo: repo) { body in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if let mood = body.mood { Text(mood.emoji) }
                            Text(body.text)
                                .lineLimit(2)
                            Spacer()
                        }
                        if !body.tags.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(body.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(AppTheme.primaryColor.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Repository unavailable").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
        .contextMenu {
            Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
```

- [ ] **Step 3.4: Add RepositoryBridge view**

Append to the file:

```swift
/// Bridges `@Environment(VaultManager)` and `@Environment(\.modelContext)`
/// into an `EntryRepository` available via `\.entryRepository` to all child views.
/// Wraps the top of MainScreenView so EntryRowView and the sheets see a non-nil repo.
struct RepositoryBridge<Content: View>: View {
    @Environment(VaultManager.self) private var vault
    @Environment(\.modelContext) private var ctx
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .environment(\.entryRepository, EntryRepository(context: ctx, vault: vault))
    }
}
```

- [ ] **Step 3.5: Wrap MainScreenView body with RepositoryBridge**

In `MainScreenView.body`, find the existing `NavigationStack { ... }` at the top of `body`. Wrap it:

```swift
    var body: some View {
        RepositoryBridge {
            NavigationStack {
                // ... existing body unchanged ...
            }
        }
    }
```

Indent the existing body one level to fit inside the closure. Do not add any other modifiers between `RepositoryBridge { ... }` and `NavigationStack { ... }`.

- [ ] **Step 3.6: Neutralise the sample-data seed in release**

Find `seedSampleDataIfNeeded()`. Replace its entire body with:

```swift
    private func seedSampleDataIfNeeded() {
        // Sample data is no longer seeded into real users' databases.
        // Plan 6 deletes this method entirely. For v1.0 transitional builds
        // run by Plan 5 worker, do nothing.
        // Closes audit finding H-3.
    }
```

This stub stays until Plan 6 Task 9 step 9.2 deletes both the method and its `.onAppear` call.

- [ ] **Step 3.7: Build + run all tests**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED, all existing tests still pass (we haven't broken anything).

- [ ] **Step 3.8: Commit**

```bash
git add JournalInsight/MainScreenView.swift
git commit -m "feat(views): EntryRowView reads via EntryRepository through EntryUnlockGate"
```

---

## Task 4: Rewire AddEntrySheet and EditEntrySheet

**Files:**
- Modify: `JournalInsight/MainScreenView.swift`

- [ ] **Step 4.1: Rewrite AddEntrySheet body to use repo**

Find `AddEntrySheet`. Change its declaration:

```swift
struct AddEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.entryRepository) private var repo

    @State private var entryDate = Date()
    @State private var entryText = ""
    @State private var durationMinutes: Double = 10
    @State private var selectedMood: Mood? = nil
    @State private var selectedTags: Set<String> = []
    @State private var newTagName = ""

    // Tag suggestions are derived from in-memory cache once vault is unlocked.
    @State private var knownTags: [String] = []

    // Timer state — unchanged
    @State private var useTimer = false
    @State private var timerRunning = false
    @State private var timerSeconds: Int = 0
    @State private var timerTask: Task<Void, Never>?
```

- [ ] **Step 4.2: Replace the Tags section body**

Find the `Section("Tags") { ... }` block in `AddEntrySheet`. Replace it with:

```swift
                Section("Tags") {
                    if !knownTags.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(knownTags, id: \.self) { tag in
                                Button {
                                    if selectedTags.contains(tag) { selectedTags.remove(tag) }
                                    else { selectedTags.insert(tag) }
                                } label: {
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(selectedTags.contains(tag) ? AppTheme.primaryColor : Color.primary.opacity(0.1))
                                        .foregroundColor(selectedTags.contains(tag) ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    HStack {
                        TextField("New tag", text: $newTagName)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            // Case-insensitive dedupe
                            if let existing = knownTags.first(where: { $0.lowercased() == name.lowercased() }) {
                                selectedTags.insert(existing)
                            } else {
                                knownTags.append(name)
                                selectedTags.insert(name)
                            }
                            newTagName = ""
                        }
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
```

- [ ] **Step 4.3: Replace the Save button body**

Find the `ToolbarItem(placement: .confirmationAction) { Button("Save") { ... } }` block in `AddEntrySheet`. Replace with:

```swift
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        stopTimer()
                        let duration: TimeInterval = useTimer ? TimeInterval(timerSeconds) : durationMinutes * 60
                        let text = entryText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let mood = selectedMood
                        let tags = Array(selectedTags)
                        guard let repo else { return }
                        Task { @MainActor in
                            do {
                                try await repo.create(date: entryDate, duration: duration, text: text, mood: mood, tags: tags)
                                dismiss()
                            } catch {
                                // Stay on the sheet; user retries.
                                Logger.vault.error("create entry failed: \(error.localizedDescription, privacy: .public)")
                            }
                        }
                    }
                    .disabled(entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || repo == nil)
                }
```

- [ ] **Step 4.4: Apply equivalent changes to EditEntrySheet**

Find `EditEntrySheet`. Replace its `@Query private var allTags: [Tag]` with `@State private var knownTags: [String] = []` and `@Environment(\.entryRepository) private var repo`.

Replace the Tags section the same way as Step 4.2.

Replace the Save button:

```swift
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let text = entryText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let mood = selectedMood
                        let tags = Array(selectedTags)
                        let duration = durationMinutes * 60
                        entry.date = entryDate
                        entry.duration = duration
                        guard let repo else { return }
                        Task { @MainActor in
                            do {
                                try await repo.update(entry, text: text, mood: mood, tags: tags)
                                dismiss()
                            } catch {
                                Logger.vault.error("update entry failed: \(error.localizedDescription, privacy: .public)")
                            }
                        }
                    }
                    .disabled(entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || repo == nil)
                }
```

Replace the `.onAppear` block on `EditEntrySheet` with:

```swift
            .onAppear {
                Task { @MainActor in
                    guard let repo else { return }
                    do {
                        let body = try await repo.body(for: entry)
                        entryText = body.text
                        selectedMood = body.mood
                        selectedTags = Set(body.tags)
                    } catch {
                        Logger.vault.error("load entry for edit failed: \(error.localizedDescription, privacy: .public)")
                    }
                    entryDate = entry.date
                    durationMinutes = entry.duration / 60
                }
            }
```

- [ ] **Step 4.5: Build succeeds**

```
xcodebuild build -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4.6: Commit**

```bash
git add JournalInsight/MainScreenView.swift
git commit -m "feat(views): AddEntrySheet/EditEntrySheet save and load via EntryRepository"
```

---

## Task 5: CalendarDetailView

**Files:**
- Modify: `JournalInsight/CalendarDetailView.swift`

- [ ] **Step 5.1: Show day-cell mood emoji only on tap (lazy decrypt)**

Find the day-cell `VStack(spacing: 2) { ... }` block. The mood emoji line currently reads from `entry.mood`. With encrypted bodies, mood is no longer accessible without unlock. Replace the `if let firstMood = ...` block with a simple "has entry" indicator:

```swift
                            let dayEntries = entries.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
                            if !dayEntries.isEmpty {
                                Circle()
                                    .fill(AppTheme.primaryColor)
                                    .frame(width: 6, height: 6)
                            }
```

Mood emojis become available in the bottom-of-screen "Entries for {date}" section, where the user has tapped a day and can incur the unlock cost.

- [ ] **Step 5.2: Update the day-detail entries list**

Find the inner `ForEach(dayEntries) { entry in ... }` block. Replace its content with:

```swift
                                ForEach(dayEntries) { entry in
                                    VStack(alignment: .leading, spacing: 4) {
                                        if let repo = repo {
                                            EntryUnlockGate(entry: entry, repo: repo) { body in
                                                HStack {
                                                    if let mood = body.mood { Text(mood.emoji) }
                                                    Text(body.text).lineLimit(3)
                                                    Spacer()
                                                }
                                                if !body.tags.isEmpty {
                                                    HStack(spacing: 4) {
                                                        ForEach(body.tags, id: \.self) { tag in
                                                            Text(tag)
                                                                .font(.caption2)
                                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                                .background(AppTheme.primaryColor.opacity(0.15))
                                                                .clipShape(Capsule())
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        Text("Duration: \(Int(entry.duration) / 60) min")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    .padding(10)
                                    .background(Color.primary.opacity(0.05))
                                    .cornerRadius(8)
                                }
```

Add at the top of `CalendarView`:

```swift
    @Environment(\.entryRepository) private var repo
```

- [ ] **Step 5.3: Build succeeds**

```
xcodebuild build -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5.4: Commit**

```bash
git add JournalInsight/CalendarDetailView.swift
git commit -m "feat(views): CalendarView day-cells use plaintext metadata, day-detail decrypts via gate"
```

---

## Task 6: SessionDetailView, StreakDetailView, QuestionsDetailView

**Files:**
- Modify: `JournalInsight/SessionDetailView.swift`
- Modify: `JournalInsight/StreakDetailView.swift`
- Modify: `JournalInsight/QuestionsDetailView.swift`

- [ ] **Step 6.1: SessionDetailView — guard mood chart**

Find the `Section("Mood Distribution")` block. Wrap it in a guard so it only renders when at least one entry has been decrypted into the cache. Simpler: render it as a "Tap to unlock" card that calls into the repo lazily.

Replace `private var moodDistribution` with:

```swift
    @Environment(\.entryRepository) private var repo
    @State private var moodDistribution: [(mood: Mood, count: Int)] = []
    @State private var moodLoadAttempted = false

    private func loadMoodDistribution() async {
        guard !moodLoadAttempted else { return }
        moodLoadAttempted = true
        guard let repo else { return }
        var counts: [Mood: Int] = [:]
        for entry in entries {
            do {
                let body = try await repo.body(for: entry)
                if let mood = body.mood { counts[mood, default: 0] += 1 }
            } catch {
                continue
            }
        }
        moodDistribution = counts.map { ($0.key, $0.value) }
            .sorted { $0.0.rawValue < $1.0.rawValue }
    }
```

In the body, replace the `if !moodDistribution.isEmpty { Section("Mood Distribution") { ... } }` block with:

```swift
                Section("Mood Distribution") {
                    if moodDistribution.isEmpty {
                        Button { Task { await loadMoodDistribution() } } label: {
                            Label("Unlock to see mood breakdown", systemImage: "lock.fill")
                        }
                    } else {
                        Chart(moodDistribution, id: \.mood) { item in
                            BarMark(
                                x: .value("Mood", item.mood.emoji),
                                y: .value("Count", item.count)
                            )
                            .foregroundStyle(colorForMood(item.mood).gradient)
                            .cornerRadius(4)
                        }
                        .frame(height: 160)
                    }
                }
```

Recent Entries section: replace its body with `EntryUnlockGate` per row similar to Task 3.

- [ ] **Step 6.2: StreakDetailView — total entries unchanged (count of plaintext rows)**

`StreakDetailView` reads `entries.count` for "Total Entries" and uses `StreakCalculator` which only reads `date`. Both work without unlock.  No changes needed except removing dependency on `entry.mood` if any (`preferredTimeOfDay` reads `entry.date`, which is plaintext — fine).

- [ ] **Step 6.3: QuestionsDetailView — save through repo**

Find the `Save` button:

```swift
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let fullText: String
                            if let prompt = selectedPrompt {
                                fullText = "\(prompt)\n\n\(answerText.trimmingCharacters(in: .whitespacesAndNewlines))"
                            } else {
                                fullText = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            let mood = selectedMood
                            guard let repo else { return }
                            Task { @MainActor in
                                do {
                                    try await repo.create(date: Date(), duration: 0, text: fullText, mood: mood, tags: [])
                                    showingEntry = false
                                } catch {
                                    Logger.vault.error("prompt entry save failed: \(error.localizedDescription, privacy: .public)")
                                }
                            }
                        }
                        .disabled(answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || repo == nil)
                    }
```

Add at the top of the view:

```swift
    @Environment(\.entryRepository) private var repo
```

- [ ] **Step 6.4: Build + run all tests**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: All existing tests pass.

- [ ] **Step 6.5: Commit**

```bash
git add JournalInsight/SessionDetailView.swift JournalInsight/StreakDetailView.swift JournalInsight/QuestionsDetailView.swift
git commit -m "feat(views): rewire Session/Streak/Questions views to use EntryRepository"
```

---

## Task 7: Audit fixes for StreakCalculator (H-1 + H-2)

**Files:**
- Modify: `JournalInsight/StreakCalculator.swift`
- Modify: `JournalInsightTests/JournalInsightTests.swift`

- [ ] **Step 7.1: Append failing tests**

In `JournalInsightTests/JournalInsightTests.swift`, find the `StreakCalculatorTests` suite. Add:

```swift
    @Test("Best streak survives DST boundary")
    func bestStreakAcrossDST() {
        // Construct entries that span a US DST transition (2nd Sunday of March 2026).
        // Spring-forward 2026: March 8.
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.timeZone = TimeZone(identifier: "America/Los_Angeles")
        components.year = 2026; components.month = 3; components.day = 7; components.hour = 12
        let day1 = calendar.date(from: components)!
        components.day = 8
        let day2 = calendar.date(from: components)!
        components.day = 9
        let day3 = calendar.date(from: components)!
        let entries = [day1, day2, day3].map { JournalEntry(date: $0, text: "x", duration: 600) }
        #expect(StreakCalculator.bestStreak(from: entries) == 3)
    }

    @Test("Preferred time of day uses circular mean for night-owl entries")
    func preferredTimeCircularMean() {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date())
        let entries = [23, 0, 1].compactMap { hour -> JournalEntry? in
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base).map {
                JournalEntry(date: $0, text: "x", duration: 600)
            }
        }
        // Arithmetic mean would be 8 → "Morning". Circular mean is ~0 → "Night".
        let result = StreakCalculator.preferredTimeOfDay(from: entries)
        #expect(result == "Night")
    }
```

- [ ] **Step 7.2: Run tests to verify they fail**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/StreakCalculator
```
Expected: 2 of the new tests FAIL (legacy implementation has bugs).

- [ ] **Step 7.3: Fix bestStreak (DST-safe)**

Replace `StreakCalculator.bestStreak`:

```swift
    static func bestStreak(from entries: [JournalEntry]) -> Int {
        let calendar = Calendar.current
        let uniqueDays = Set(entries.map { calendar.startOfDay(for: $0.date) }).sorted()
        guard !uniqueDays.isEmpty else { return 0 }

        var best = 1
        var current = 1

        for i in 1..<uniqueDays.count {
            let prev = uniqueDays[i - 1]
            let next = uniqueDays[i]
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: prev),
               calendar.isDate(nextDay, inSameDayAs: next) {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }
```

- [ ] **Step 7.4: Fix preferredTimeOfDay (circular mean)**

Replace `StreakCalculator.preferredTimeOfDay`:

```swift
    static func preferredTimeOfDay(from entries: [JournalEntry]) -> String {
        guard !entries.isEmpty else { return "—" }
        let calendar = Calendar.current
        let radians: [Double] = entries.map {
            let hour = Double(calendar.component(.hour, from: $0.date))
            return hour * .pi / 12.0                                     // 0…2π
        }
        let sumSin = radians.reduce(0.0) { $0 + sin($1) }
        let sumCos = radians.reduce(0.0) { $0 + cos($1) }
        let n = Double(radians.count)
        let meanRad = atan2(sumSin / n, sumCos / n)
        let rawHour = meanRad * 12.0 / .pi
        let meanHour = (rawHour + 24.0).truncatingRemainder(dividingBy: 24.0)
        switch meanHour {
        case ..<7:    return "Early Morning"
        case 7..<12:  return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default:      return "Night"
        }
    }
```

- [ ] **Step 7.5: Run tests to verify they pass**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/StreakCalculator
```
Expected: All StreakCalculator tests pass.

- [ ] **Step 7.6: Commit**

```bash
git add JournalInsight/StreakCalculator.swift JournalInsightTests/JournalInsightTests.swift
git commit -m "fix(streak): DST-safe bestStreak comparison and circular-mean preferredTimeOfDay (audit H-1, H-2)"
```

---

## Plan-5 acceptance

- [ ] All 5 EntryRepository tests pass.
- [ ] All StreakCalculator tests including 2 new ones pass.
- [ ] `xcodebuild build` succeeds for the whole scheme.
- [ ] No view in the app reads `JournalEntry.text`, `mood`, or `tags` directly any more — all goes through `EntryRepository` / `EntryUnlockGate`.
- [ ] Manual: run on simulator, create new entry → save → verify it appears in list with "Tap to unlock" pill on first read.

When all seven tasks are checked, this plan is complete.
