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
| `AppTheme.swift` | 2026-03-24 | Added `AppAppearance`, `CalendarScope`, `StorageKeys` |
| `MainScreenView.swift` | 2026-03-24 | SwiftData `@Query`, add-entry sheet, nav title, responsive widgets, widget card icons |
| `CalendarDetailView.swift` | 2026-03-24 | Uses `@Query` instead of passed-in entries, DST-safe date math |
| `SettingsView.swift` | 2026-03-24 | `@AppStorage` via `StorageKeys`, auto-dismiss saved indicator, wallpaper file storage |
| `StreakDetailView.swift` | 2026-03-24 | Data-driven streaks via `StreakCalculator`, `@Query` |
| `SessionDetailView.swift` | 2026-03-24 | Full implementation with stats from `@Query` entries |
| `QuestionsDetailView.swift` | 2026-03-24 | Journaling prompts with entry creation |
| `GoalsDetailView.swift` | 2026-03-24 | Full goal CRUD with progress tracking via SwiftData |
| `JournalEntry.swift` | 2026-03-24 | Converted to SwiftData `@Model` class |
| `JournalInsightApp.swift` | 2026-03-24 | Added `.modelContainer` for `JournalEntry` and `Goal` |
| `Goal.swift` | 2026-03-24 | **NEW** — SwiftData `@Model` for goals |
| `StreakCalculator.swift` | 2026-03-24 | **NEW** — Extracted testable streak/time-of-day logic |
| `JournalInsightTests.swift` | 2026-03-24 | 16 real tests: streak, goal, wallpaper storage, entry, keys |

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

<!-- ADD NEW SESSIONS BELOW THIS LINE -->



---

## File Index

A running index of key files in the project — updated by Claude as new files are created or significantly changed.

| File | Role | Notes |
|------|------|-------|
| `AppTheme.swift` | Theme constants & shared enums | Colors, `AppAppearance`, `CalendarScope`, `StorageKeys` |
| `JournalEntry.swift` | Data model | SwiftData `@Model` class |
| `Goal.swift` | Data model | SwiftData `@Model` for goals with progress tracking |
| `StreakCalculator.swift` | Business logic | Testable streak computation utilities |
| `JournalInsightApp.swift` | App entry point | Model container for `JournalEntry` + `Goal`, appearance |
| `MainScreenView.swift` | Main dashboard | Widget grid, add-entry sheet, name prompt |
| `CalendarDetailView.swift` | Calendar detail view | Multi-scope calendar with `@Query` entries |
| `SettingsView.swift` | Settings/personalization | Name, wallpaper, appearance, `WallpaperStorage` |
| `StreakDetailView.swift` | Streak stats | Data-driven via `StreakCalculator` |
| `SessionDetailView.swift` | Session KPIs | Stats computed from `@Query` entries |
| `QuestionsDetailView.swift` | Journaling prompts | Daily prompts, creates entries on save |
| `GoalsDetailView.swift` | Goals tracking | CRUD goals with progress bars |
| `JournalInsightTests.swift` | Unit tests | 16 tests across 5 suites |

---

## Known Issues / TODO

Items identified during sessions that need follow-up:

- `WidgetDropDelegate` uses `NSItemProvider` with string UUIDs — consider `Transferable` protocol for type-safe drag-and-drop
- Widget layout/order is not persisted — resets on relaunch
- No edit/delete flow for journal entries (only create)
- No iCloud sync configured for SwiftData (requires entitlements)
- Calendar view always shows current month/week — no month navigation
- QuestionsDetailView prompt rotation is deterministic but not customizable
- UI tests are still boilerplate — could add real interaction tests

---

## Notes for Claude

- This is an **Xcode / Swift / iOS** project using **SwiftData** for persistence
- Prefer **Swift best practices**: `async/await`, `@MainActor`, value types where possible
- Use **SwiftUI** unless UIKit is already established in the file
- Use `StorageKeys` enum for all `UserDefaults` / `@AppStorage` key strings
- Models: `JournalEntry` and `Goal` are SwiftData `@Model` classes
- When suggesting changes, always show the **before/after** diff in code blocks
- Flag any **breaking changes**, deprecated APIs, or potential **memory leaks**
- If you see a pattern repeated across files, suggest a **refactor**
