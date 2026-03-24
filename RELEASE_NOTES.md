# JournalInsight — Release Notes

## Version 1.0.0

**Date:** March 24, 2026

---

### What's New

#### Journal Entries with Persistent Storage
Your journal entries are now saved on-device using SwiftData. Entries persist across app launches — no more losing your writing when you close the app.

#### Create New Entries
Tap the **+** button in the toolbar to add a new journal entry. Pick a date, write your thoughts, and set the session duration with an intuitive slider (1–120 minutes).

#### Streak Tracking
See your current consecutive-day journaling streak, your all-time best streak, your most active time of day, and total entry count. The flame icon lights up orange when you're on a streak.

#### Session Statistics
The Session KPIs screen now shows real data:
- Total entries and total journaling time
- Average session duration and longest session
- Entries written this week
- A list of your 5 most recent entries

#### Daily Journaling Prompts
The Questions screen provides 3 daily prompts rotated from a library of 10 thoughtful questions like *"What are you grateful for today?"* and *"What did you learn today?"*. Tap any prompt to write a response that saves directly as a journal entry.

#### Goal Tracking
Set personal goals with target dates and track your progress:
- Add goals with a title and deadline
- Adjust progress in 10% increments with a stepper
- Color-coded progress bars: teal (in progress), green (complete), red (overdue)
- Swipe to delete goals you no longer need

#### Multi-Scope Calendar
View your journaling history across five different calendar scopes:
- Month, Work Week, Full Week, 2 Weeks, and 4 Weeks
- Days with entries are marked with a teal dot
- Tap a day to view the full entry text and duration

#### Personalization
- Set your display name (shown in the welcome greeting)
- Choose a wallpaper image from your photo library
- Switch between System, Light, and Dark appearance modes

---

### Improvements

#### Responsive Widget Layout
Dashboard widgets now adapt to your screen size instead of using fixed pixel widths. Each widget displays an icon for easier identification at a glance.

#### Proper Navigation
Fixed double navigation bars that appeared on the Settings screen. All detail views now use consistent, standard iOS navigation with proper back buttons and inline titles.

#### DST-Safe Calendar
Calendar date calculations now use proper `Calendar` APIs instead of raw second arithmetic, so week boundaries display correctly during Daylight Saving Time transitions.

#### Performance
- Widget row IDs are now stable across renders, eliminating unnecessary SwiftUI redraws
- Date formatters are allocated once (static) instead of on every frame
- Wallpaper images are stored on the file system instead of in UserDefaults

#### Settings Feedback
The "Saved!" confirmation in Settings now auto-dismisses after 2 seconds.

---

### Under the Hood

- **SwiftData** adopted for persistent storage of journal entries and goals
- **16 unit tests** covering streak calculation, goal validation, wallpaper storage, and data model initialization — all passing
- Consolidated all `UserDefaults` keys into a single `StorageKeys` enum
- Extracted streak computation logic into a testable `StreakCalculator` utility
- Removed all deprecated API usage (`onChange`, `UIWindowScene.windows`, `@available` annotations)
- Fixed file naming issue (`StreakDetailView .swift` trailing space)

---

### Known Limitations

- Journal entries can be created but not edited or deleted yet
- Widget arrangement via drag-and-drop resets on relaunch
- Calendar view is anchored to the current month — no forward/back navigation yet
- iCloud sync is not yet configured

---

### System Requirements

- iOS 17.0 or later
- Xcode 16.0 or later (for development)
