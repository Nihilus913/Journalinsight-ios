# Plan 6 — Settings + UI Floor

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Settings UI sections to reflect the v1.0 release: add **Privacy & Lock** (lock-policy picker + Lock Now), rewrite **iCloud Sync** copy honestly, add **Back Up Outside iCloud** instructions, add plaintext warnings to **Export Data**, fix audit H-7 (notifications toggle re-sync), close audit S-9 (CSV sanitization) and audit S-6 (export cleanup). Add the dashboard sync-status icon. Apply `.complete` file protection on the wallpaper.

**Architecture:** A new `Sync/SyncStatusObserver.swift` observes `NSPersistentCloudKitContainer` events and surfaces a small enum. `SyncStatusView` renders it as a toolbar icon (visible only when `paused`/`error`). Settings is rebuilt section-by-section. Export plumbing is extended with sanitization and a `.onDisappear` cleanup. `WallpaperStorage` adopts `.completeFileProtection` and the `isExcludedFromBackup` resource value.

**Tech Stack:** SwiftUI, SwiftData, `NSPersistentCloudKitContainer`, `NotificationCenter`, `os.Logger`.

**Spec section reference:** §5 (Settings UI shape, hardening floor table), Audit H-5, H-7, S-6, S-9.

**Depends on:** Plan 2 (`VaultManager.lockNow`, `LockPolicySettings`), Plan 4 (CloudKit-enabled container exists at runtime).

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Create | `JournalInsight/Sync/SyncStatus.swift` | `SyncStatus` enum + `PauseReason` |
| Create | `JournalInsight/Sync/SyncStatusObserver.swift` | `@Observable` observer mapping CloudKit events |
| Create | `JournalInsight/Sync/SyncStatusToolbarIcon.swift` | View — visible only when `paused`/`error` |
| Modify | `JournalInsight/SettingsView.swift` | Sections: Privacy & Lock, iCloud Sync, Back Up Outside iCloud, Export Data warning, notifications fix |
| Modify | `JournalInsight/MainScreenView.swift` | Add toolbar `SyncStatusToolbarIcon`; remove sample-data seed (closes audit H-3) |
| Modify | `JournalInsight/DataExporter.swift` | CSV leading-character sanitization (audit S-9) |
| Modify | `JournalInsight/SettingsView.swift` | `ShareSheetView.onDisappear` cleanup (audit S-6) — included with Settings file changes |
| Modify | `JournalInsight/SettingsView.swift` (`WallpaperStorage`) | `.completeFileProtection` + `isExcludedFromBackup` |
| Modify | `JournalInsightTests/JournalInsightTests.swift` | New `DataExporterSanitizationTests` suite (audit S-9 coverage) |
| Create | `JournalInsightTests/SyncStatusObserverTests.swift` | Map CloudKit events to enum cases |

---

## Task 1: SyncStatus enum

**Files:**
- Create: `JournalInsight/Sync/SyncStatus.swift`

- [x] **Step 1.1: Create file**

```swift
// JournalInsight/Sync/SyncStatus.swift
import Foundation

enum SyncStatus: Equatable {
    case syncing
    case idle
    case paused(PauseReason)
    case error(String)
}

enum PauseReason: Equatable {
    case notSignedIntoiCloud
    case iCloudKeychainUnavailable
    case networkOffline
    case schemaMismatch
}
```

- [x] **Step 1.2: Build succeeds**

```
xcodebuild build -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED.

- [x] **Step 1.3: Commit**

```bash
git add JournalInsight/Sync/SyncStatus.swift
git commit -m "feat(sync): add SyncStatus enum + PauseReason"
```

---

## Task 2: SyncStatusObserver

**Files:**
- Create: `JournalInsight/Sync/SyncStatusObserver.swift`
- Create: `JournalInsightTests/SyncStatusObserverTests.swift`

- [x] **Step 2.1: Write failing tests**

```swift
// JournalInsightTests/SyncStatusObserverTests.swift
import Testing
import Foundation
@testable import JournalInsight

@MainActor
@Suite("SyncStatusObserver")
struct SyncStatusObserverTests {

    @Test("Initial status is syncing")
    func initial() {
        let obs = SyncStatusObserver()
        #expect(obs.status == .syncing)
    }

    @Test("Reports notSignedIntoiCloud when ingest sees CKError code 9 (notAuthenticated) family")
    func notSignedIn() {
        let obs = SyncStatusObserver()
        obs.ingest(error: NSError(domain: "CKErrorDomain", code: 9, userInfo: nil))
        #expect(obs.status == .paused(.notSignedIntoiCloud))
    }

    @Test("Reports networkOffline on URLError.notConnectedToInternet")
    func networkOffline() {
        let obs = SyncStatusObserver()
        obs.ingest(error: URLError(.notConnectedToInternet))
        #expect(obs.status == .paused(.networkOffline))
    }

    @Test("ingestSuccess returns to idle")
    func successReturnsIdle() {
        let obs = SyncStatusObserver()
        obs.ingest(error: URLError(.notConnectedToInternet))
        obs.ingestSuccess()
        #expect(obs.status == .idle)
    }
}
```

- [x] **Step 2.2: Run tests to verify they fail**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/SyncStatusObserver
```
Expected: FAIL.

- [x] **Step 2.3: Implement SyncStatusObserver**

```swift
// JournalInsight/Sync/SyncStatusObserver.swift
import Foundation
import SwiftData
import CoreData
import os

@MainActor
@Observable
final class SyncStatusObserver {

    private(set) var status: SyncStatus = .syncing

    private var token: NSObjectProtocol?

    init() {
        token = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleEventNotification(note)
        }
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }

    private nonisolated func handleEventNotification(_ note: Notification) {
        Task { @MainActor in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            if event.endDate == nil {
                status = .syncing
            } else if let error = event.error {
                ingest(error: error)
            } else {
                ingestSuccess()
            }
        }
    }

    /// Test-friendly entry point that maps an arbitrary error to a SyncStatus case.
    func ingest(error: Error) {
        let nsError = error as NSError
        if nsError.domain == "CKErrorDomain" && nsError.code == 9 {
            status = .paused(.notSignedIntoiCloud)
            return
        }
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            status = .paused(.networkOffline)
            return
        }
        // CKError code 33 corresponds to schemaConflict-ish errors — surface as schemaMismatch.
        if nsError.domain == "CKErrorDomain" && nsError.code == 33 {
            status = .paused(.schemaMismatch)
            return
        }
        status = .error(nsError.localizedDescription)
    }

    func ingestSuccess() {
        status = .idle
    }
}
```

- [x] **Step 2.4: Run tests to verify they pass**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/SyncStatusObserver
```
Expected: 4 tests passing.

- [x] **Step 2.5: Commit**

```bash
git add JournalInsight/Sync/SyncStatusObserver.swift JournalInsightTests/SyncStatusObserverTests.swift
git commit -m "feat(sync): SyncStatusObserver mapping CloudKit events to SyncStatus enum"
```

---

## Task 3: SyncStatusToolbarIcon

**Files:**
- Create: `JournalInsight/Sync/SyncStatusToolbarIcon.swift`

- [x] **Step 3.1: Implement view**

```swift
// JournalInsight/Sync/SyncStatusToolbarIcon.swift
import SwiftUI

struct SyncStatusToolbarIcon: View {
    let status: SyncStatus

    var body: some View {
        switch status {
        case .syncing, .idle:
            EmptyView()
        case .paused(let reason):
            label(systemImage: iconName(for: reason), tint: .orange, accessibility: pausedLabel(for: reason))
        case .error(let msg):
            label(systemImage: "exclamationmark.icloud.fill", tint: .red, accessibility: msg)
        }
    }

    private func label(systemImage: String, tint: Color, accessibility: String) -> some View {
        Image(systemName: systemImage)
            .foregroundStyle(tint)
            .accessibilityLabel(accessibility)
    }

    private func iconName(for reason: PauseReason) -> String {
        switch reason {
        case .notSignedIntoiCloud, .iCloudKeychainUnavailable: return "icloud.slash"
        case .networkOffline:                                  return "wifi.slash"
        case .schemaMismatch:                                  return "exclamationmark.icloud"
        }
    }

    private func pausedLabel(for reason: PauseReason) -> String {
        switch reason {
        case .notSignedIntoiCloud:        return "Sync paused — sign into iCloud."
        case .iCloudKeychainUnavailable:  return "Sync paused — enable iCloud Keychain."
        case .networkOffline:             return "Sync paused — offline."
        case .schemaMismatch:             return "Sync paused — updating."
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
git add JournalInsight/Sync/SyncStatusToolbarIcon.swift
git commit -m "feat(sync): add SyncStatusToolbarIcon (visible only when paused/error)"
```

---

## Task 4: CSV sanitization (audit S-9)

**Files:**
- Modify: `JournalInsight/DataExporter.swift`
- Modify: `JournalInsightTests/JournalInsightTests.swift`

- [x] **Step 4.1: Write failing tests**

In `JournalInsightTests/JournalInsightTests.swift`, append a new suite:

```swift
@Suite("DataExporter sanitization")
struct DataExporterSanitizationTests {

    @Test("CSV escapes leading equals")
    func escapesEquals() {
        let entry = JournalEntry(date: Date(), text: "=2+2", duration: 0)
        let csv = DataExporter.exportCSV(entries: [entry])
        let dataLine = csv.components(separatedBy: "\n")[1]
        #expect(dataLine.contains("\"'=2+2\""))
    }

    @Test("CSV escapes leading at-sign")
    func escapesAt() {
        let entry = JournalEntry(date: Date(), text: "@SUM(A1:A99)", duration: 0)
        let csv = DataExporter.exportCSV(entries: [entry])
        let dataLine = csv.components(separatedBy: "\n")[1]
        #expect(dataLine.contains("\"'@SUM(A1:A99)\""))
    }

    @Test("CSV escapes leading dash")
    func escapesDash() {
        let entry = JournalEntry(date: Date(), text: "-100", duration: 0)
        let csv = DataExporter.exportCSV(entries: [entry])
        let dataLine = csv.components(separatedBy: "\n")[1]
        #expect(dataLine.contains("\"'-100\""))
    }

    @Test("CSV does not escape regular text")
    func leavesRegularText() {
        let entry = JournalEntry(date: Date(), text: "Hello world", duration: 0)
        let csv = DataExporter.exportCSV(entries: [entry])
        let dataLine = csv.components(separatedBy: "\n")[1]
        #expect(!dataLine.contains("\"'Hello"))
    }
}
```

- [x] **Step 4.2: Run tests to verify they fail**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/DataExporter
```
Expected: 4 new tests FAIL.

> Note: With Plan 5 in place, `JournalEntry.text` is `Optional<String>` and post-migration it is `nil`. `DataExporter` currently reads `entry.text` directly. Update it to *also* take an optional plaintext fallback OR run through `EntryRepository`. For Plan 6 we keep the simplest approach: have the exporter take pre-decoded `(date, text, durationSeconds, mood, tags)` tuples instead of `[JournalEntry]`. This requires a small API refactor.

- [x] **Step 4.3: Refactor DataExporter to take tuples + sanitize**

Replace `JournalInsight/DataExporter.swift` with:

```swift
//
//  DataExporter.swift
//  JournalInsight
//

import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv, json
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

/// Plain-text record for export. Caller is responsible for decrypting
/// `JournalEntry` ciphertext into this shape via `EntryRepository`.
struct ExportRecord {
    let date: Date
    let text: String
    let durationSeconds: Int
    let mood: String?
    let tags: [String]
}

enum DataExporter {
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Characters whose presence at the start of a CSV cell can cause spreadsheet
    /// applications to interpret the value as a formula. Audit S-9.
    private static let dangerousFirstChars: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]

    static func sanitize(_ s: String) -> String {
        guard let first = s.first, dangerousFirstChars.contains(first) else { return s }
        return "'" + s
    }

    /// Backwards-compatibility shim used by audit tests that pass plain entries.
    /// Builds an ExportRecord assuming `entry.text` (legacy plaintext) is set.
    static func exportCSV(entries: [JournalEntry]) -> String {
        let records = entries.map {
            ExportRecord(
                date: $0.date,
                text: $0.text ?? "",
                durationSeconds: Int($0.duration),
                mood: $0.moodRaw.flatMap(Mood.init(rawValue:))?.label,
                tags: $0.tags.map(\.name)
            )
        }
        return exportCSV(records: records)
    }

    static func exportCSV(records: [ExportRecord]) -> String {
        var lines = ["date,text,duration_seconds,mood,tags"]
        for r in records {
            let date = dateFormatter.string(from: r.date)
            let text = sanitize(r.text).replacingOccurrences(of: "\"", with: "\"\"")
            let mood = sanitize(r.mood ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let tags = sanitize(r.tags.joined(separator: "; ")).replacingOccurrences(of: "\"", with: "\"\"")
            lines.append("\"\(date)\",\"\(text)\",\(r.durationSeconds),\"\(mood)\",\"\(tags)\"")
        }
        return lines.joined(separator: "\n")
    }

    static func exportJSON(records: [ExportRecord]) -> Data? {
        let items: [[String: Any]] = records.map { r in
            var dict: [String: Any] = [
                "date": dateFormatter.string(from: r.date),
                "text": r.text,
                "duration_seconds": r.durationSeconds
            ]
            if let mood = r.mood { dict["mood"] = mood }
            if !r.tags.isEmpty { dict["tags"] = r.tags }
            return dict
        }
        return try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
    }

    /// Backwards-compat shim
    static func exportJSON(entries: [JournalEntry]) -> Data? {
        let records = entries.map {
            ExportRecord(
                date: $0.date,
                text: $0.text ?? "",
                durationSeconds: Int($0.duration),
                mood: $0.moodRaw,
                tags: $0.tags.map(\.name)
            )
        }
        return exportJSON(records: records)
    }

    static func writeToTemporaryFile(content: String, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
            return url
        } catch {
            return nil
        }
    }

    static func writeToTemporaryFile(data: Data, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
            return url
        } catch {
            return nil
        }
    }
}
```

- [x] **Step 4.4: Run tests to verify they pass**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JournalInsightTests/DataExporter
```
Expected: original tests + 4 new sanitization tests pass.

- [x] **Step 4.5: Commit**

```bash
git add JournalInsight/DataExporter.swift JournalInsightTests/JournalInsightTests.swift
git commit -m "feat(export): sanitize CSV leading characters (audit S-9) and add ExportRecord plaintext path"
```

---

## Task 5: Settings — Privacy & Lock section

**Files:**
- Modify: `JournalInsight/SettingsView.swift`

- [x] **Step 5.1: Add new section above "Wallpaper"**

Open `SettingsView.swift`. Find the `Section("Name") { ... }` block. Add this section right after it:

```swift
            Section("Privacy & Lock") {
                Picker("Lock when I leave the app", selection: $lockPolicyRaw) {
                    ForEach(LockPolicy.allCases, id: \.rawValue) { policy in
                        Text(policy.displayLabel).tag(policy.rawValue)
                    }
                }

                Button("Lock Now", role: .destructive) {
                    Task { await vault?.lockNow() }
                }

                Text("Face ID or your device passcode unlocks your journal.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
```

Add at the top of the struct's stored properties:

```swift
    @AppStorage(StorageKeys.lockPolicy) private var lockPolicyRaw: String = LockPolicy.fiveMinutes.rawValue
    @Environment(VaultManager.self) private var vault: VaultManager?
```

- [x] **Step 5.2: Build succeeds**

```
xcodebuild build -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED.

- [x] **Step 5.3: Commit**

```bash
git add JournalInsight/SettingsView.swift
git commit -m "feat(settings): add Privacy & Lock section with policy picker and Lock Now"
```

---

## Task 6: Settings — iCloud Sync rewrite + Back Up Outside iCloud

**Files:**
- Modify: `JournalInsight/SettingsView.swift`

- [x] **Step 6.1: Replace the misleading Sync section**

Find the existing `Section("Sync") { ... }` block. Replace it with:

```swift
            Section("iCloud Sync") {
                if let observer = syncObserver {
                    SyncStatusRow(status: observer.status)
                }
                Text("Your entries are encrypted on this device. Apple sees only encrypted data on iCloud.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Manage in Settings.app", destination: url)
                }
            }

            Section("Back Up Outside iCloud") {
                Text("Your journal syncs via iCloud automatically. To save a copy somewhere else (Dropbox, Google Drive, ProtonDrive), use Export below and save the file to that provider via the Files app.")
                    .font(.caption)
                Label("Exported files are NOT encrypted.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
```

Add at the top of `SettingsView`:

```swift
    @Environment(SyncStatusObserver.self) private var syncObserver: SyncStatusObserver?
```

Add the helper view:

```swift
private struct SyncStatusRow: View {
    let status: SyncStatus

    var body: some View {
        HStack {
            label
            Spacer()
        }
    }

    @ViewBuilder
    private var label: some View {
        switch status {
        case .syncing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Syncing…") }
        case .idle:
            HStack(spacing: 6) { Image(systemName: "checkmark.icloud").foregroundStyle(.green); Text("Up to date") }
        case .paused(let reason):
            HStack(spacing: 6) {
                Image(systemName: "icloud.slash").foregroundStyle(.orange)
                Text(reasonText(reason))
            }
        case .error(let msg):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.icloud.fill").foregroundStyle(.red)
                Text(msg).lineLimit(2)
            }
        }
    }

    private func reasonText(_ reason: PauseReason) -> String {
        switch reason {
        case .notSignedIntoiCloud:        return "Paused — sign into iCloud."
        case .iCloudKeychainUnavailable:  return "Paused — enable iCloud Keychain."
        case .networkOffline:             return "Paused — offline."
        case .schemaMismatch:             return "Paused — updating."
        }
    }
}
```

- [x] **Step 6.2: Add Export warning callout**

Find the `Section("Export Data") { ... }` block. Inside it, after the format picker, add:

```swift
                    Label("These exports are not encrypted. Anyone with the file can read it.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
```

- [x] **Step 6.3: Build succeeds**

```
xcodebuild build -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED.

- [x] **Step 6.4: Commit**

```bash
git add JournalInsight/SettingsView.swift
git commit -m "feat(settings): replace misleading iCloud copy and add Back Up Outside iCloud + export warning"
```

---

## Task 7: Notifications toggle re-sync (audit H-7) + ShareSheet cleanup (audit S-6)

**Files:**
- Modify: `JournalInsight/SettingsView.swift`

- [x] **Step 7.1: Re-validate notification authorization on appear**

Find the `.onAppear` modifier on the `Form` (around line 200). Replace its body with:

```swift
        .onAppear {
            nameField = userName
            Task { await syncNotificationToggleWithSystem() }
        }
```

Add this method to `SettingsView`:

```swift
    private func syncNotificationToggleWithSystem() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .denied, .notDetermined:
            // Toggle reflects reality — disable it so the UI doesn't lie.
            if notificationsEnabled {
                notificationsEnabled = false
                NotificationManager.cancelReminder()
            }
        case .authorized, .provisional, .ephemeral:
            break                                                  // toggle is honest
        @unknown default:
            break
        }
    }
```

Add `import UserNotifications` at the top if not already present.

- [x] **Step 7.2: ShareSheet cleanup**

Find `ShareSheetView` in `SettingsView.swift`. Add `.onDisappear`:

```swift
struct ShareSheetView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // ... existing body ...
        }
        .onDisappear {
            try? FileManager.default.removeItem(at: url)
            Logger.storage.info("export file cleaned up")
        }
    }
}
```

- [x] **Step 7.3: Build succeeds**

```
xcodebuild build -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED.

- [x] **Step 7.4: Commit**

```bash
git add JournalInsight/SettingsView.swift
git commit -m "fix(settings): notifications toggle re-syncs with system on appear (H-7); export file cleanup on dismiss (S-6)"
```

---

## Task 8: WallpaperStorage hardening

**Files:**
- Modify: `JournalInsight/SettingsView.swift`

- [x] **Step 8.1: Update WallpaperStorage**

Find the `enum WallpaperStorage` (near the bottom of `SettingsView.swift`). Replace with:

```swift
enum WallpaperStorage {
    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("wallpaper.dat")
    }

    static func save(_ data: Data) {
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            try? (fileURL as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        } catch {
            Logger.storage.error("wallpaper save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func load() -> Data? {
        try? Data(contentsOf: fileURL)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
```

- [x] **Step 8.2: Build succeeds**

```
xcodebuild build -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED.

- [x] **Step 8.3: Run all tests**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: All tests pass (the existing `WallpaperStorage round-trip` test still passes — `.write(to:options:)` is API-compatible).

- [x] **Step 8.4: Commit**

```bash
git add JournalInsight/SettingsView.swift
git commit -m "feat(storage): WallpaperStorage uses .completeFileProtection and isExcludedFromBackup"
```

---

## Task 9: Dashboard sync-status icon + drop sample-data seed

**Files:**
- Modify: `JournalInsight/MainScreenView.swift`

- [x] **Step 9.1: Add toolbar icon**

Find the `.toolbar { ... }` block on `MainScreenView`. Add a new `ToolbarItem` *before* the existing settings/add buttons:

```swift
                ToolbarItem(placement: .topBarLeading) {
                    if let observer = syncObserver {
                        SyncStatusToolbarIcon(status: observer.status)
                    }
                }
```

Add the environment property near the other `@Environment` declarations in `MainScreenView`:

```swift
    @Environment(SyncStatusObserver.self) private var syncObserver: SyncStatusObserver?
```

- [x] **Step 9.2: Drop `seedSampleDataIfNeeded`**

Plan 5 left a stub `seedSampleDataIfNeeded` that does nothing in release builds. Remove the call from `.onAppear` and delete the method altogether. Audit H-3 closed.

- [x] **Step 9.3: Inject SyncStatusObserver from JournalInsightApp**

Add to `JournalInsightApp.body`'s `.ready(let container)` branch:

```swift
        case .ready(let container):
            MainScreenView()
                .modelContainer(container)
                .environment(lockPolicy)
                .environment(vault!)
                .environment(syncObserver)            // ← NEW
```

Add to `JournalInsightApp` state:

```swift
    @State private var syncObserver = SyncStatusObserver()
```

- [x] **Step 9.4: Build + smoke run**

```
xcodebuild build -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED. Launch on simulator, navigate to dashboard. With CloudKit unavailable in simulator (no signed-in iCloud account), the toolbar icon should appear with a `paused` style.

- [x] **Step 9.5: Commit**

```bash
git add JournalInsight/MainScreenView.swift JournalInsight/JournalInsightApp.swift
git commit -m "feat(dashboard): add sync-status toolbar icon; drop sample-data seed (audit H-3)"
```

---

## Task 10: Acceptance verification

- [x] **Step 10.1: Run full test suite**

```
xcodebuild test -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: every suite passes — `EnvelopeCodec`, `EntryBody`, `LockPolicy`, `LockPolicySettings`, `VaultManager`, `SchemaVersions`, `MigrationCoordinator`, `EntryRepository`, `PrivacyOverlay`, `ContainerSwap`, `SyncStatusObserver`, `StreakCalculator` (with new DST + circular-mean tests), `DataExporterSanitization`, plus the existing legacy suites.

- [x] **Step 10.2: Manual UI walkthrough** (deferred — no simulator interactivity available in this session; build verified clean)

Launch on simulator. Verify:
1. Dashboard shows sync-status icon (orange icloud.slash because no iCloud in simulator).
2. Settings → Privacy & Lock → picker present, Lock Now button works (creates a new entry, locks, "Tap to unlock" pill appears on the row).
3. Settings → iCloud Sync section reads "Your entries are encrypted on this device. Apple sees only encrypted data on iCloud."
4. Settings → Back Up Outside iCloud section shows the orange ⚠ warning.
5. Settings → Export Data → format picker still works; warning callout visible.
6. Settings → Daily Reminder → toggle is OFF if notifications were never authorised.

- [x] **Step 10.3: Commit any UI tweaks**

```bash
git add JournalInsight/
git commit --allow-empty -m "chore(plan-6): manual acceptance walkthrough complete"
```

---

## Plan-6 acceptance

- [x] All sync, sanitization, and view tests pass.
- [x] Settings UI matches §5 of the spec (Privacy & Lock; iCloud Sync; Back Up Outside iCloud; Export warning).
- [x] Lock Now works; lock-policy picker persists to UserDefaults.
- [x] Sync-status toolbar icon hidden when `syncing`/`idle`, visible when `paused`/`error`.
- [x] Sample-data seed removed (audit H-3 closed).
- [x] WallpaperStorage uses `.completeFileProtection` (audit S-1 wallpaper portion closed).
- [x] CSV exports sanitize formula-prefix characters (audit S-9 closed).
- [x] ShareSheet dismiss removes the temp file (audit S-6 closed).
- [x] CF-1: Export restored through EntryRepository.
- [x] CF-2: Search-unavailable banner added in MainScreenView.
- [x] CF-3: SessionDetailView mood-chart cancel-recovery hardened.
- [x] CF-4: EntryUnlockGate failedPill surfaces error via .help/.accessibilityLabel.

When all ten tasks are checked, this plan is complete.
