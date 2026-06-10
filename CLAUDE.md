# CLAUDE.md — Xcode Project Change Tracker

This file instructs Claude on how to track, log, and summarize all code changes made during our sessions. Place this file in the **root of your Xcode project**.

---

## Instructions for Claude

When working on this Xcode project, you must:

1. **Log every change** in the `## Change Log` section below
2. **Track files edited** in the `## Files Modified` section
3. **Summarize diffs** clearly — what changed, why, and what it affects
4. **Update the session block** at the start of each conversation
5. **Never overwrite old entries** — always append new ones

---

## How to Use This File

### Starting a session
Paste the contents of this file into the chat. Claude will read the history and continue from where you left off.

### Ending a session
Ask Claude: *"Update CLAUDE.md with today's changes"* — Claude will give you the updated file to save back into your project.

### Git tip
Commit this file alongside your code changes:
```bash
git add CLAUDE.md && git commit -m "docs: update Claude change log"
```

---

## Files Modified

| File | Last Modified | Summary |
|------|--------------|---------|
| `AppTheme.swift` | 2026-03-25 | Added `AccentColorChoice`, `TextSizeChoice`, notification/widget storage keys |
| `MainScreenView.swift` | 2026-03-25 | Search, edit/delete entries, timer, tags, mood, live widget data, persist layout |
| `CalendarDetailView.swift` | 2026-03-25 | Month navigation (back/forward/today), mood emojis on calendar dots |
| `SettingsView.swift` | 2026-03-25 | Accent color, text size, notification reminders, data export, iCloud info |
| `StreakDetailView.swift` | 2026-03-25 | Milestone tracking with progress bars and celebration banners |
| `SessionDetailView.swift` | 2026-03-25 | Swift Charts: weekly entries bar chart, duration trend line, mood distribution |
| `QuestionsDetailView.swift` | 2026-03-25 | Mood selection when creating entries from prompts |
| `GoalsDetailView.swift` | 2026-03-24 | Full goal CRUD with progress tracking via SwiftData |
| `JournalEntry.swift` | 2026-03-25 | Added `Mood` enum, `Tag` model, mood/tags properties |
| `JournalInsightApp.swift` | 2026-03-25 | Tag model container, dynamic type size, tint color |
| `Goal.swift` | 2026-03-24 | **NEW** — SwiftData `@Model` for goals |
| `StreakCalculator.swift` | 2026-03-24 | **NEW** — Extracted testable streak/time-of-day logic |
| `JournalInsightTests.swift` | 2026-03-25 | 39 unit tests across 12 suites covering all features |
| `NotificationManager.swift` | 2026-03-25 | **NEW** — Daily reminder scheduling via UNUserNotificationCenter |
| `DataExporter.swift` | 2026-03-25 | **NEW** — CSV/JSON export for journal entries |

---

## Change Log

### Session — 2026-03-24 (Session 1)
**Goal:** Full code review and fix all high/medium priority issues
**Files touched:** AppTheme.swift, MainScreenView.swift, CalendarDetailView.swift, SettingsView.swift, StreakDetailView.swift, JournalEntry.swift
**Changes:**
- [SettingsView.swift] Removed nested `NavigationStack` that caused double nav bars and broken back-button. Removed `@available(iOS 16.0, *)` annotations. Fixed deprecated `onChange(of:)` to use new two-parameter signature. Replaced `@AppStorage` wallpaper image data with file-system-based `WallpaperStorage` utility. Used modern `.textFieldStyle(.roundedBorder)` shorthand.
- [MainScreenView.swift] Replaced `widgetRows` computed property that generated new `UUID()` per render with stable `WidgetRow` struct using IDs derived from widget content. Replaced hardcoded pixel widths (160/336) with `GeometryReader`-based responsive sizing. Removed `.ignoresSafeArea()` and manual `safeAreaTopInset()` that used deprecated `UIWindowScene.windows` API. Modernized preview to `#Preview` macro.
- [CalendarDetailView.swift] Replaced `86400`-seconds-per-day arithmetic with `Calendar.date(from:)` using `yearForWeekOfYear`/`weekOfYear` components for DST safety. Made `dayFormatter` and `fullFormatter` `static let` instead of computed properties to avoid repeated allocation. Removed redundant `.navigationBarBackButtonHidden(false)`.
- [StreakDetailView.swift] Renamed file from `StreakDetailView .swift` (trailing space). Removed duplicate `#Preview` block.
- [AppTheme.swift] Moved `AppAppearance` enum (from SettingsView.swift) and `CalendarScope` enum (from JournalEntry.swift) here as shared type definitions.
- [JournalEntry.swift] Removed `CalendarScope` enum (moved to AppTheme.swift).
**Diff summary:** Fixed 11 issues across 6 files — navigation bugs, render performance, DST correctness, deprecated API usage, file naming, and code organization.
**Status:** Done

### Session — 2026-03-24 (Session 2)
**Goal:** Implement all 9 suggested updates from the code review
**Files touched:** All source files + 2 new files + tests
**Changes:**
- [JournalEntry.swift] Converted from `struct` to SwiftData `@Model class`. ID is now auto-managed by SwiftData.
- [Goal.swift] **NEW FILE** — SwiftData `@Model` for goals with title, targetDate, and progress (clamped 0...1).
- [StreakCalculator.swift] **NEW FILE** — Extracted streak computation (current streak, best streak, preferred time of day) from StreakDetailView into a testable utility enum.
- [AppTheme.swift] Added `StorageKeys` enum to consolidate all `UserDefaults` keys.
- [JournalInsightApp.swift] Added `import SwiftData`, `.modelContainer(for: [JournalEntry.self, Goal.self])`, and switched to `StorageKeys.selectedAppearance`.
- [MainScreenView.swift] Major rewrite:
  - Replaced `@State` entries array with `@Query` from SwiftData.
  - Added `@AppStorage(StorageKeys.userName)` to auto-sync name across views.
  - Added `AddEntrySheet` with date picker, text editor, and duration slider.
  - Added `+` button in toolbar and settings gear in toolbar.
  - Added `.navigationTitle` with proper `.large` display mode.
  - Replaced `GeometryReader` with `maxWidth: .infinity` flexible layout.
  - Added `WidgetCardView` with SF Symbol icons per widget type.
  - Seeds sample data on first launch.
  - Extracted `NamePromptSheet` into its own struct.
- [CalendarDetailView.swift] Switched from passed-in `entries` parameter to `@Query`. Removed the `entries` init parameter.
- [SettingsView.swift] Replaced raw `UserDefaults` reads with `@AppStorage(StorageKeys.userName)`. Added auto-dismiss for "Saved!" indicator after 2 seconds. Cleaned up to use proper Form-based layout.
- [SessionDetailView.swift] Full implementation: total entries, total time, average duration, longest session, entries this week, and recent entries list — all computed from `@Query`.
- [QuestionsDetailView.swift] Full implementation: 10 journaling prompts rotated daily (3 per day), tap to open a response sheet that saves a `JournalEntry` via SwiftData.
- [GoalsDetailView.swift] Full implementation: goals list from `@Query`, add/delete goals, progress stepper with color-coded progress bars (green=complete, red=overdue, teal=in progress).
- [StreakDetailView.swift] Now uses `@Query` and `StreakCalculator` for real data-driven streaks. Shows flame icon, current streak, best streak, preferred time of day, total entries.
- [JournalInsightTests.swift] Replaced empty test boilerplate with 16 real tests across 5 suites: StreakCalculator (11 tests), JournalEntry (1 test), Goal (2 tests), WallpaperStorage (1 test), StorageKeys (1 test). All pass.
**Diff summary:** Adopted SwiftData persistence, added entry creation flow, built out all placeholder views, added data-driven streaks, consolidated UserDefaults, and added 16 unit tests. 2 new files created.
**Status:** Done

---

### Session — 2026-03-25 (Session 3)
**Goal:** Implement 14 new features (edit/delete, search, mood, timer, notifications, calendar nav, tags, export, charts, milestones, live widgets, iCloud, theme/text size, persist layout)
**Files touched:** All source files + 2 new files + tests
**Changes:**
- [JournalEntry.swift] Added `Mood` enum (5 moods with emoji/label), `Tag` SwiftData `@Model` with unique name constraint, `moodRaw`/`mood` computed property, `tags` relationship on `JournalEntry`.
- [AppTheme.swift] Added `AccentColorChoice` enum (6 color options), `TextSizeChoice` enum (4 sizes mapped to `DynamicTypeSize`), new `StorageKeys` for accent color, text size, notifications, and widget layout.
- [JournalInsightApp.swift] Registered `Tag.self` in model container. Applied `.dynamicTypeSize()` and `.tint()` from user preferences.
- [NotificationManager.swift] **NEW FILE** — `UNUserNotificationCenter` wrapper for requesting authorization, scheduling daily reminders, and cancelling them.
- [DataExporter.swift] **NEW FILE** — CSV and JSON export with mood/tag support, temp file writing utilities.
- [MainScreenView.swift] Major rewrite:
  - Feature #1: `EntryRowView` with context menu edit/delete, `EditEntrySheet` for editing entries, delete confirmation dialog.
  - Feature #2: `.searchable()` modifier with local filtering on text, mood, and tags.
  - Feature #3: Mood picker in `AddEntrySheet` with emoji buttons.
  - Feature #4: Timer mode toggle with start/pause/reset using async `Task.sleep`.
  - Feature #7: Tag picker with flow layout, create-new-tag inline field.
  - Feature #11: `WidgetCardView` shows live streak count, entry count, this-week count.
  - Feature #14: Widget layout saved/loaded via JSON in `UserDefaults`.
  - Moved `WidgetType`, `WidgetSize`, `WidgetItem` to file scope as `Codable` enums/structs.
  - Added `FlowLayout` custom `Layout` for tag chips.
- [CalendarDetailView.swift] Feature #6: Month navigation with chevron buttons and "Today" reset. Shows mood emojis instead of plain dots. Shows all entries for selected day with mood/tags. Navigation animates between months/weeks.
- [SessionDetailView.swift] Feature #9: Swift Charts integration — `BarMark` for weekly entry counts, `LineMark`+`AreaMark` for duration trends, `BarMark` for mood distribution. Added mood emoji in recent entries.
- [StreakDetailView.swift] Feature #10: Milestone tracking for 7/14/30/50/100/200/365 days. Progress bar to next milestone. Celebration banner with star animation on milestone days. Uses `symbolEffect(.bounce)`.
- [SettingsView.swift] Feature #5: Notification toggle with authorization request, hour/minute pickers. Feature #8: Export format picker (CSV/JSON) with `ShareLink`. Feature #12: iCloud sync info section. Feature #13: Accent color picker and text size segmented control. Replaced "Coming Soon" placeholders.
- [QuestionsDetailView.swift] Added mood picker in the prompt response sheet.
- [JournalInsightTests.swift] Expanded from 16 to 39 unit tests across 12 suites: added Mood (4 tests), Tag (1 test), JournalEntry mood/tags (4 tests), DataExporter CSV/JSON (7 tests), WidgetLayout Codable (2 tests), AccentColorChoice (2 tests), TextSizeChoice (2 tests), expanded StorageKeys (1 test with 8 assertions).
**Diff summary:** 14 features implemented, 2 new files, all existing views updated, test count increased from 16 to 39. All 42 tests pass (39 unit + 3 UI).
**Status:** Done

<!-- ADD NEW SESSIONS BELOW THIS LINE -->



---

## File Index

A running index of key files in the project — updated by Claude as new files are created or significantly changed.

| File | Role | Notes |
|------|------|-------|
| `AppTheme.swift` | Theme constants & shared enums | Colors, `AppAppearance`, `CalendarScope`, `AccentColorChoice`, `TextSizeChoice`, `StorageKeys` |
| `JournalEntry.swift` | Data models | `JournalEntry` @Model, `Tag` @Model, `Mood` enum |
| `Goal.swift` | Data model | SwiftData `@Model` for goals with progress tracking |
| `StreakCalculator.swift` | Business logic | Testable streak computation utilities |
| `NotificationManager.swift` | Notifications | Daily reminder scheduling via `UNUserNotificationCenter` |
| `DataExporter.swift` | Export | CSV/JSON export with mood/tag support |
| `JournalInsightApp.swift` | App entry point | Model container, dynamic type size, tint color |
| `MainScreenView.swift` | Main dashboard | Widget grid, search, edit/delete, timer, tags, mood, persist layout |
| `CalendarDetailView.swift` | Calendar detail view | Month navigation, mood emojis, multi-scope |
| `SettingsView.swift` | Settings/personalization | Name, wallpaper, accent color, text size, notifications, export, iCloud |
| `StreakDetailView.swift` | Streak stats | Milestones, celebration banners, progress to next milestone |
| `SessionDetailView.swift` | Session KPIs | Swift Charts: entries, duration, mood distribution |
| `QuestionsDetailView.swift` | Journaling prompts | Daily prompts with mood selection |
| `GoalsDetailView.swift` | Goals tracking | CRUD goals with progress bars |
| `JournalInsightTests.swift` | Unit tests | 39 tests across 12 suites |

---

## Known Issues / TODO

Items identified during sessions that need follow-up:

- `WidgetDropDelegate` uses `NSItemProvider` with string IDs — consider `Transferable` protocol for type-safe drag-and-drop
- iCloud sync requires CloudKit entitlement and container configuration in Xcode project settings
- QuestionsDetailView prompt rotation is deterministic but not customizable
- UI tests are still boilerplate — could add real interaction tests
- Notification permissions may need to be re-requested if denied initially

---

## Notes for Claude

- This is an **Xcode / Swift / iOS** project using **SwiftData** for persistence
- Prefer **Swift best practices**: `async/await`, `@MainActor`, value types where possible
- Use **SwiftUI** unless UIKit is already established in the file
- Use `StorageKeys` enum for all `UserDefaults` / `@AppStorage` key strings
- Models: `JournalEntry`, `Goal`, and `Tag` are SwiftData `@Model` classes
- When suggesting changes, always show the **before/after** diff in code blocks
- Flag any **breaking changes**, deprecated APIs, or potential **memory leaks**
- If you see a pattern repeated across files, suggest a **refactor**
