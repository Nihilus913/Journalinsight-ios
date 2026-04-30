//
//  SettingsView.swift
//  JournalInsight
//
//  Created by Tobias Tensfeldt on 25.04.2025.
//

import SwiftUI
import SwiftData
import PhotosUI
import UserNotifications
import os
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    @AppStorage(StorageKeys.userName) private var userName: String = ""
    @State private var nameField: String = ""
    @State private var showSaved = false
    @State private var wallpaperImageData: Data? = WallpaperStorage.load()
    @AppStorage(StorageKeys.selectedAppearance) private var selectedAppearance: AppAppearance = .system
    @AppStorage(StorageKeys.accentColor) private var accentColorChoice: AccentColorChoice = .teal
    @AppStorage(StorageKeys.textSize) private var textSize: TextSizeChoice = .medium
    @AppStorage(StorageKeys.notificationsEnabled) private var notificationsEnabled: Bool = false
    @AppStorage(StorageKeys.notificationHour) private var notificationHour: Int = 20
    @AppStorage(StorageKeys.notificationMinute) private var notificationMinute: Int = 0
    @AppStorage(StorageKeys.lockPolicy) private var lockPolicyRaw: String = LockPolicy.fiveMinutes.rawValue
    @Environment(\.vault) private var vault: VaultManager?
    @Environment(\.entryRepository) private var entryRepository
    @Environment(SyncStatusObserver.self) private var syncObserver: SyncStatusObserver?
    @State private var showImagePicker = false
    @State private var selectedItem: PhotosPickerItem? = nil

    // Export (Feature #8)
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @State private var showExportSheet = false
    @State private var exportFormat: ExportFormat = .csv
    @State private var exportURL: URL?
    @State private var exportInProgress = false
    @State private var exportError: String?

    var body: some View {
        Form {
            Section("Name") {
                TextField("Your name", text: $nameField)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    userName = nameField.trimmingCharacters(in: .whitespacesAndNewlines)
                    showSaved = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        showSaved = false
                    }
                }
                .disabled(nameField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if showSaved {
                    Text("Saved!")
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
            }

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

            Section("Wallpaper") {
                Button {
                    showImagePicker.toggle()
                } label: {
                    Label("Select New Wallpaper", systemImage: "photo")
                }

                #if canImport(UIKit)
                if let data = wallpaperImageData, let uiImage = UIImage(data: data) {
                    NavigationLink(destination: FullscreenWallpaperView(imageData: data)) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 100)
                            .clipped()
                            .cornerRadius(8)
                            .padding(.top, 8)
                    }
                }
                #endif

                if wallpaperImageData != nil {
                    Button("Remove Wallpaper", role: .destructive) {
                        wallpaperImageData = nil
                        WallpaperStorage.delete()
                    }
                }
            }

            // Feature #13: Theme
            Section("Accent Color") {
                Picker("Accent Color", selection: $accentColorChoice) {
                    ForEach(AccentColorChoice.allCases) { choice in
                        HStack {
                            Circle()
                                .fill(choice.color)
                                .frame(width: 16, height: 16)
                            Text(choice.label)
                        }
                        .tag(choice)
                    }
                }
            }

            // Feature #13: Text Size
            Section("Text Size") {
                Picker("Text Size", selection: $textSize) {
                    ForEach(TextSizeChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            Section("Appearance") {
                Picker("Appearance", selection: $selectedAppearance) {
                    Text("System").tag(AppAppearance.system)
                    Text("Light").tag(AppAppearance.light)
                    Text("Dark").tag(AppAppearance.dark)
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            // Feature #5: Notification Reminders
            Section("Daily Reminder") {
                Toggle("Enable Reminder", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if enabled {
                            Task {
                                let granted = await NotificationManager.requestAuthorization()
                                if granted {
                                    NotificationManager.scheduleDailyReminder(hour: notificationHour, minute: notificationMinute)
                                } else {
                                    notificationsEnabled = false
                                }
                            }
                        } else {
                            NotificationManager.cancelReminder()
                        }
                    }

                if notificationsEnabled {
                    HStack {
                        Text("Reminder Time")
                        Spacer()
                        Picker("Hour", selection: $notificationHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(String(format: "%02d", h)).tag(h)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        Text(":")
                        Picker("Minute", selection: $notificationMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    .onChange(of: notificationHour) { _, _ in
                        NotificationManager.scheduleDailyReminder(hour: notificationHour, minute: notificationMinute)
                    }
                    .onChange(of: notificationMinute) { _, _ in
                        NotificationManager.scheduleDailyReminder(hour: notificationHour, minute: notificationMinute)
                    }
                }
            }

            // Feature #8: Data Export — routed through EntryRepository (Plan 6 / CF-1)
            Section("Export Data") {
                if entries.isEmpty {
                    Text("No entries to export")
                        .foregroundColor(.secondary)
                } else {
                    Picker("Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases) { fmt in
                            Text(fmt.label).tag(fmt)
                        }
                    }
                    .pickerStyle(.segmented)

                    Label("These exports are not encrypted. Anyone with the file can read it.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Button {
                        Task { await generateExport() }
                    } label: {
                        if exportInProgress {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Preparing export…")
                            }
                        } else {
                            Label("Export \(entries.count) entr\(entries.count == 1 ? "y" : "ies")", systemImage: "square.and.arrow.up")
                        }
                    }
                    .disabled(exportInProgress || entryRepository == nil)

                    if let exportError {
                        Text(exportError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

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
        }
        .navigationTitle("Personalize")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            nameField = userName
            Task { await syncNotificationToggleWithSystem() }
        }
        .onChange(of: selectedItem) { _, newItem in
            if let newItem {
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        wallpaperImageData = data
                        WallpaperStorage.save(data)
                    }
                }
            }
        }
        .photosPicker(isPresented: $showImagePicker, selection: $selectedItem)
        .sheet(isPresented: $showExportSheet) {
            if let url = exportURL {
                ShareSheetView(url: url)
            }
        }
    }

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

    @MainActor
    private func generateExport() async {
        guard let repo = entryRepository else {
            exportError = "Vault unavailable. Try again."
            return
        }
        exportInProgress = true
        exportError = nil
        defer { exportInProgress = false }

        // Decrypt each entry through the repository (will trigger biometric once if locked).
        var records: [ExportRecord] = []
        records.reserveCapacity(entries.count)
        for entry in entries {
            do {
                let body = try await repo.body(for: entry)
                records.append(
                    ExportRecord(
                        date: entry.date,
                        text: body.text,
                        durationSeconds: Int(entry.duration),
                        mood: body.mood?.label,
                        tags: body.tags
                    )
                )
            } catch VaultError.userCancelled {
                exportError = "Export cancelled."
                return
            } catch {
                Logger.crypto.error("export decrypt failed: \(error.localizedDescription, privacy: .public)")
                exportError = "Couldn't decrypt one or more entries."
                return
            }
        }

        switch exportFormat {
        case .csv:
            let csv = DataExporter.exportCSV(records: records)
            if let url = DataExporter.writeToTemporaryFile(content: csv, filename: "journal_entries.csv") {
                exportURL = url
                showExportSheet = true
            } else {
                exportError = "Couldn't write export file."
            }
        case .json:
            if let data = DataExporter.exportJSON(records: records),
               let url = DataExporter.writeToTemporaryFile(data: data, filename: "journal_entries.json") {
                exportURL = url
                showExportSheet = true
            } else {
                exportError = "Couldn't write export file."
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheetView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                Text("Export Ready")
                    .font(.title2)
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)

                ShareLink(item: url) {
                    Label("Share File", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onDisappear {
            try? FileManager.default.removeItem(at: url)
            Logger.storage.info("export file cleaned up")
        }
    }
}

/// Stores wallpaper image on the file system instead of UserDefaults.
enum WallpaperStorage {
    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("wallpaper.dat")
    }

    static func save(_ data: Data) {
        try? data.write(to: fileURL)
    }

    static func load() -> Data? {
        try? Data(contentsOf: fileURL)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

struct FullscreenWallpaperView: View {
    let imageData: Data

    var body: some View {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: imageData) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            .navigationTitle("Wallpaper")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            Text("Unable to load image")
                .foregroundColor(.secondary)
                .navigationTitle("Wallpaper")
                .navigationBarTitleDisplayMode(.inline)
        }
        #else
        Text("Image preview not available on this platform.")
            .foregroundColor(.secondary)
            .navigationTitle("Wallpaper")
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Sync Status Row

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

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [JournalEntry.self, Tag.self], inMemory: true)
}
