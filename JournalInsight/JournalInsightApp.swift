//
//  JournalInsightApp.swift
//  JournalInsight
//
//  Created by Tobias Tensfeldt on 25.04.2025.
//

import SwiftUI
import SwiftData

@main
struct JournalInsightApp: App {
    @AppStorage(StorageKeys.selectedAppearance) private var selectedAppearance: AppAppearance = .system
    @AppStorage(StorageKeys.textSize) private var textSize: TextSizeChoice = .medium
    @AppStorage(StorageKeys.accentColor) private var accentColorChoice: AccentColorChoice = .teal

    var body: some Scene {
        WindowGroup {
            MainScreenView()
                .preferredColorScheme(selectedAppearance == .light ? .light : selectedAppearance == .dark ? .dark : nil)
                .dynamicTypeSize(textSize.sizeCategory)
                .tint(accentColorChoice.color)
                .frame(minWidth: 400, minHeight: 600)
        }
        .modelContainer(for: [JournalEntry.self, Goal.self, Tag.self])
    }
}
