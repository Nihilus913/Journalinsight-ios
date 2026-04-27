# JournalInsight — Release Notes

## Version 2.0.0

**Date:** March 25, 2026

---

### What's New

#### Edit & Delete Journal Entries
Long-press any entry on the dashboard to edit or delete it. Editing opens a full sheet with all fields pre-populated. Deletion requires confirmation to prevent accidental data loss.

#### Full-Text Search
A search bar at the top of the dashboard lets you filter entries by text content, mood, or tag name. Results update instantly as you type.

#### Mood Tracking
Record how you're feeling with each entry. Choose from five moods — Great, Good, Okay, Bad, and Terrible — each with a distinct emoji. Moods appear on entry rows, calendar days, session charts, and in exported data.

#### Journaling Timer
Toggle between a manual duration slider and a live stopwatch timer when creating entries. Start, pause, and reset the timer as needed — the elapsed time is saved automatically when you save the entry.

#### Daily Reminder Notifications
Set a daily reminder to journal at a specific time. Enable notifications in Settings, choose your preferred hour and minute, and the app schedules a recurring local notification. Reminders can be toggled off at any time.

#### Calendar Month Navigation
Navigate forward and backward through months, weeks, or multi-week periods using chevron buttons. A "Today" button snaps you back to the current date. Navigation works across all five calendar scopes.

#### Entry Tags & Categories
Create and assign tags to journal entries. Tags appear as capsule chips on entry rows and in the calendar detail view. The tag picker uses a flow layout and supports creating new tags inline.

#### Data Export (CSV & JSON)
Export all journal entries from Settings in CSV or JSON format. Exports include date, text, duration, mood, and tags. Share the exported file via the system share sheet.

#### Session Charts
The Session KPIs screen now includes three interactive charts built with Swift Charts:
- **Entries This Week** — bar chart showing daily entry counts for the past 7 days
- **Duration Trend** — line and area chart showing journaling minutes per day
- **Mood Distribution** — bar chart breaking down mood frequency across all entries

#### Streak Milestones & Celebrations
Track your progress toward seven milestone levels: 7, 14, 30, 50, 100, 200, and 365 days. A progress bar shows how close you are to the next milestone. When you reach one, a celebration banner with star animations appears automatically.

#### Live Dashboard Widgets
Widget cards on the main screen now display live data summaries:
- **Streak Info** shows your current streak count
- **Session KPIs** shows total entry count
- **Calendar Overview** shows entries written this week

#### Theme & Accent Color
Choose from six accent colors (Teal, Blue, Purple, Orange, Pink, Green) in Settings. The selected color applies app-wide as the tint color for buttons, links, and interactive elements.

#### Adjustable Text Size
Select from four text sizes (Small, Medium, Large, Extra Large) in Settings. The setting overrides the system Dynamic Type size for the entire app.

#### Persistent Widget Layout
Widget order and sizes are now saved automatically. Rearrange widgets via drag-and-drop or resize via context menu, and your layout persists across app launches.

#### iCloud Sync Ready
The data layer is configured for iCloud sync via SwiftData. To enable sync, add a CloudKit container entitlement to the Xcode project and configure the `ModelConfiguration` with `.cloudKitDatabase(.automatic)`.

---

### Improvements

#### Mood on Prompts
The journaling prompts screen now includes a mood picker, so entries created from prompts also record your emotional state.

#### Calendar Mood Indicators
Calendar days now show the mood emoji of the first entry for that day instead of a plain dot. Days without mood data still show the teal dot indicator.

#### Multi-Entry Calendar View
Selecting a day on the calendar now shows all entries for that day (not just the first), each with mood, text, duration, and tags.

---

### Under the Hood

- **2 new files**: `NotificationManager.swift` (notification scheduling), `DataExporter.swift` (CSV/JSON export)
- **39 unit tests** across 12 test suites — up from 16 tests in v1.0. New coverage for mood, tags, data export, widget layout persistence, accent colors, and text size settings.
- **42 total tests** (39 unit + 3 UI) — all passing
- `Mood` enum with `Codable` conformance stored as raw string in SwiftData
- `Tag` SwiftData model with unique name constraint
- `FlowLayout` custom SwiftUI `Layout` for tag chip display
- `WidgetItem` and `WidgetType` are now `Codable` for JSON persistence
- `AccentColorChoice` and `TextSizeChoice` enums mapped to SwiftUI `Color` and `DynamicTypeSize`
- All new `StorageKeys` for notifications, accent color, text size, and widget layout

---

### Previous Known Limitations — Resolved

| Limitation (v1.0) | Resolution (v2.0) |
|---|---|
| Entries could not be edited or deleted | Edit and delete via context menu |
| Widget layout reset on relaunch | Layout persisted in UserDefaults as JSON |
| Calendar had no month navigation | Forward/back/today navigation added |
| iCloud sync not configured | Data layer ready; requires entitlement |

### Remaining Known Limitations

- iCloud sync requires adding a CloudKit container entitlement in the Xcode project
- Notification permissions cannot be re-requested from within the app if denied at the system level
- QuestionsDetailView prompt rotation is deterministic (not randomized)
- UI tests are still boilerplate — could be expanded with real interaction tests

---

### System Requirements

- iOS 17.0 or later
- Xcode 16.0 or later (for development)
