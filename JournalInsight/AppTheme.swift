//
//  AppTheme.swift
//  JournalInsight
//
//  Created by Tobias Tensfeldt on 25.04.2025.
//

import SwiftUI

struct AppTheme {
    static let primaryColor = Color.teal
    static let secondaryColor = Color.gray
    static let accentColor = Color.orange
    static let backgroundColor = Color(.systemBackground)
    static let textColor = Color.primary
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
}

enum CalendarScope: String, CaseIterable, Identifiable {
    case month, workWeek, fullWeek, twoWeeks, fourWeeks
    var id: String { self.rawValue }
}

enum AccentColorChoice: String, CaseIterable, Identifiable {
    case teal, blue, purple, orange, pink, green

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .teal: return .teal
        case .blue: return .blue
        case .purple: return .purple
        case .orange: return .orange
        case .pink: return .pink
        case .green: return .green
        }
    }

    var label: String { rawValue.capitalized }
}

enum TextSizeChoice: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    var sizeCategory: DynamicTypeSize {
        switch self {
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .extraLarge: return .xxxLarge
        }
    }
}

enum StorageKeys {
    static let userName = "userName"
    static let selectedAppearance = "selectedAppearance"
    static let accentColor = "accentColor"
    static let textSize = "textSize"
    static let notificationsEnabled = "notificationsEnabled"
    static let notificationHour = "notificationHour"
    static let notificationMinute = "notificationMinute"
    static let widgetLayout = "widgetLayout"
}
