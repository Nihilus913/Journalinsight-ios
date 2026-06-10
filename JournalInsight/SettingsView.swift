//
//  SettingsView.swift
//  JournalInsight
//
//  Created by Tobias Tensfeldt on 25.04.2025.
//

import SwiftUI
import SwiftData
import PhotosUI
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
    @AppStorage(StorageKeys.workoutReminderEnabled) private var workoutReminderEnabled: Bool = false
    @AppStorage(StorageKeys.workoutReminderHour) private var workoutReminderHour: Int = 7
    @AppStorage(StorageKeys.workoutReminderMinute) private var workoutReminderMinute: Int = 0
    @AppStorage(StorageKeys.healthKitEnabled) private var healthKitEnabled: Bool = false
    @State private var workoutDays: [Int] = []
    @State private var showImagePicker = false
    @State private var selectedItem: PhotosPickerItem? = nil

    // Export (Feature #8)
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @State private var showExportSheet = false
    @State private var exportFormat: ExportFormat = .csv
    @State private var exportURL: URL?

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

            // Feature #8: Data Export
            Section("Export Data") {
                if entries.isEmpty {
                    Text("No entries to export")
                        .foregroundColor(.secondary)
                } else {
                    Picker("Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    Button {
                        generateExport()
                    } label: {
                        Label("Export \(entries.count) Entries", systemImage: "square.and.arrow.up")
                    }
                }
            }

            // Feature #12: iCloud Sync
            Section("Sync") {
                VStack(alignment: .leading, spacing: 4) {
                    Label("iCloud Sync", systemImage: "icloud.fill")
                        .font(.body)
                    Text("Data syncs automatically via iCloud when the app is configured with a CloudKit container.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Training") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workout days")
                        .font(.subheadline)
                    // Calendar.weekday is 1-indexed: 1=Sunday, 2=Monday, …, 7=Saturday.
                    HStack(spacing: 6) {
                        ForEach(Array(zip([1,2,3,4,5,6,7], ["S","M","T","W","T","F","S"])), id: \.0) { day, label in
                            let isSelected = workoutDays.contains(day)
                            Button(label) {
                                if isSelected { workoutDays.removeAll { $0 == day } }
                                else { workoutDays.append(day) }
                                saveWorkoutDays()
                                rescheduleWorkoutReminders()
                            }
                            .frame(width: 36, height: 36)
                            .background(isSelected ? Color.orange : Color.gray.opacity(0.15))
                            .foregroundStyle(isSelected ? .white : .primary)
                            .clipShape(Circle())
                            .font(.caption.weight(.semibold))
                        }
                    }
                }

                Toggle("Workout reminder", isOn: $workoutReminderEnabled)
                    .onChange(of: workoutReminderEnabled) { _, enabled in
                        if enabled {
                            Task {
                                let granted = await NotificationManager.requestAuthorization()
                                if !granted { workoutReminderEnabled = false }
                                else { rescheduleWorkoutReminders() }
                            }
                        } else {
                            NotificationManager.cancelWorkoutReminders()
                        }
                    }

                if workoutReminderEnabled {
                    HStack {
                        Text("Reminder time")
                        Spacer()
                        Picker("Hour", selection: $workoutReminderHour) {
                            ForEach(4..<13, id: \.self) { h in
                                Text(String(format: "%02d", h)).tag(h)
                            }
                        }
                        .pickerStyle(.menu).labelsHidden()
                        Text(":")
                        Picker("Minute", selection: $workoutReminderMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .pickerStyle(.menu).labelsHidden()
                    }
                    .onChange(of: workoutReminderHour) { _, _ in rescheduleWorkoutReminders() }
                    .onChange(of: workoutReminderMinute) { _, _ in rescheduleWorkoutReminders() }
                }

                // Apple Health connection — gates HKObserver startup on next launch
                Toggle("Connect Apple Health", isOn: $healthKitEnabled)
                    .onChange(of: healthKitEnabled) { _, enabled in
                        guard enabled, HealthKitPermissions.isAvailable else { return }
                        Task {
                            try? await HealthKitPermissions.shared.requestAuthorization(
                                toShare: HealthKitPermissions.writeTypes,
                                read: HealthKitPermissions.readTypes
                            )
                            // Observer will start on next app launch when healthKitEnabled is now true.
                        }
                    }

                HStack {
                    Label("Garmin Connect", systemImage: "applewatch")
                    Spacer()
                    Text("Connect in SP4")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Personalize")
        .inlineNavigationTitle()
        .onAppear {
            nameField = userName
            if let data = UserDefaults.standard.data(forKey: StorageKeys.workoutDays),
               let days = try? JSONDecoder().decode([Int].self, from: data) {
                workoutDays = days
            } else {
                workoutDays = [2, 5]
                saveWorkoutDays()
            }
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

    private func generateExport() {
        switch exportFormat {
        case .csv:
            let csv = DataExporter.exportCSV(entries: entries)
            if let url = DataExporter.writeToTemporaryFile(content: csv, filename: "journal_entries.csv") {
                exportURL = url
                showExportSheet = true
            }
        case .json:
            if let data = DataExporter.exportJSON(entries: entries),
               let url = DataExporter.writeToTemporaryFile(data: data, filename: "journal_entries.json") {
                exportURL = url
                showExportSheet = true
            }
        }
    }

    private func saveWorkoutDays() {
        if let data = try? JSONEncoder().encode(workoutDays) {
            UserDefaults.standard.set(data, forKey: StorageKeys.workoutDays)
        }
    }

    private func rescheduleWorkoutReminders() {
        guard workoutReminderEnabled else { return }
        NotificationManager.scheduleWorkoutReminder(
            weekdays: workoutDays,
            hour: workoutReminderHour,
            minute: workoutReminderMinute,
            planSummary: ""
        )
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
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
            .inlineNavigationTitle()
        } else {
            Text("Unable to load image")
                .foregroundColor(.secondary)
                .navigationTitle("Wallpaper")
                .inlineNavigationTitle()
        }
        #else
        Text("Image preview not available on this platform.")
            .foregroundColor(.secondary)
            .navigationTitle("Wallpaper")
            .inlineNavigationTitle()
        #endif
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [JournalEntry.self, Tag.self], inMemory: true)
}
