//
//  JournalInsightApp.swift
//  JournalInsight
//
//  Created by Tobias Tensfeldt on 25.04.2025.
//

import SwiftUI
import SwiftData
import BackgroundTasks
import HealthKit

@main
struct JournalInsightApp: App {
    @AppStorage(StorageKeys.selectedAppearance) private var selectedAppearance: AppAppearance = .system
    @AppStorage(StorageKeys.textSize) private var textSize: TextSizeChoice = .medium
    @AppStorage(StorageKeys.accentColor) private var accentColorChoice: AccentColorChoice = .teal

    @State private var healthStore = HKHealthStore()
    @State private var hkObserver: HealthKitObserver?

    var body: some Scene {
        WindowGroup {
            MainScreenView()
                .preferredColorScheme(selectedAppearance == .light ? .light : selectedAppearance == .dark ? .dark : nil)
                .dynamicTypeSize(textSize.sizeCategory)
                .tint(accentColorChoice.color)
                .frame(minWidth: 400, minHeight: 600)
                .task {
                    BackgroundSyncManager.registerTasks()
                    BackgroundSyncManager.scheduleNext()
                }
        }
        .modelContainer(for: [JournalEntry.self, Goal.self, Tag.self, WorkoutEntry.self]) { result in
            if case .success(let container) = result {
                let context = container.mainContext
                let observer = HealthKitObserver(store: healthStore, modelContext: context)
                hkObserver = observer

                Task { @MainActor in
                    if HealthKitPermissions.isAvailable {
                        try? await healthStore.requestAuthorization(
                            toShare: HealthKitPermissions.writeTypes,
                            read: HealthKitPermissions.readTypes
                        )
                        observer.start()
                    }
                }
            }
        }
    }
}
