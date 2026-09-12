# JournalInsight — Independent Application Audit Report

**Engagement:** Application Architecture, Security, and Quality Audit
**Date:** 2026-03-25
**Classification:** Confidential — For Management Use
**Scope:** Full codebase — 15 source files, 3 test files, 2 documentation files

---

## 1. Executive Summary

JournalInsight is a SwiftUI-based personal journaling application using SwiftData for local persistence. The application processes **sensitive personal health and wellness data** (mood tracking, personal reflections, behavioral patterns) but currently lacks the governance, architectural rigor, and compliance controls expected for a health-adjacent consumer application.

**Overall Maturity Rating: 2 out of 5 (Initial/Developing)**

| Domain | Rating | Assessment |
|---|---|---|
| Architecture | 2/5 | Monolithic view layer, no service/repository abstraction |
| Security | 2/5 | No encryption, no auth, no data classification |
| Privacy & Compliance | 1/5 | No privacy policy, no data retention, no consent management |
| Testing | 2/5 | Unit tests exist but coverage is narrow; UI tests are stubs |
| Documentation | 1/5 | No architecture docs, no API contracts, no runbooks |
| Operational Resilience | 2/5 | No error handling strategy, no logging, no crash reporting |
| Code Quality | 3/5 | Consistent style, but SRP violations and God Views |

---

## 2. Architecture Audit

### 2.1 No Architectural Pattern Documented or Enforced

**Severity: HIGH** | **Category: Governance**

The project has no architecture decision records (ADRs), no documented pattern (MVVM, MVI, Clean Architecture, TCA), and no enforced separation of concerns. The de facto pattern is "Smart Views" — views directly contain business logic, data access, formatting, and state management.

**Evidence:**

- `MainScreenView.swift` (762 lines) contains: data queries, search filtering, timer logic, widget layout persistence, drag-and-drop coordination, sample data seeding, and 7 nested structs
- `SettingsView.swift` (332 lines) contains: notification scheduling orchestration, file I/O, export generation, photo loading
- `SessionDetailView.swift` computes statistics inline as computed properties

**Impact:** High coupling, low testability, high change risk. Any modification to the data layer ripples into every view.

**Recommendation:** Adopt MVVM or a lightweight equivalent:

- Extract `@Observable` ViewModels per screen
- Introduce a Repository layer between views and SwiftData
- Document the chosen pattern in an ADR

### 2.2 No Dependency Injection / Service Locator

**Severity: MEDIUM** | **Category: Architecture**

All dependencies are resolved inline:

- `@Query` decorators couple views directly to SwiftData
- `UserDefaults.standard` is accessed directly in `loadWidgets()` (`MainScreenView.swift:218`)
- `FileManager.default` is accessed directly in `WallpaperStorage` and `DataExporter`
- `UNUserNotificationCenter.current()` is called directly in `NotificationManager`
- `Calendar.current` is used in ~15 locations

**Impact:** Impossible to substitute test doubles. Business logic that depends on "today's date" or "current calendar" cannot be deterministically tested.

**Recommendation:** Introduce protocols for external dependencies. At minimum: a `Clock` protocol for date-dependent logic, and constructor injection on ViewModels.

### 2.3 No Layered Architecture Diagram

**Severity: HIGH** | **Category: Documentation**

There is no component diagram, dependency graph, layer diagram, or module map. The codebase has no README beyond `CLAUDE.md` (a session log) and `RELEASE_NOTES.md`.

**Expected artifacts (missing):**

- C4 Model (Context, Container, Component, Code diagrams)
- Data flow diagram showing SwiftData → Views → UserDefaults
- Swimlane diagrams for key user journeys (entry creation, export, notification setup)
- Module dependency graph

### 2.4 God File — MainScreenView.swift

**Severity: MEDIUM** | **Category: Maintainability**

At 762 lines, `MainScreenView.swift` contains 12 distinct structs/types:

1. `WidgetSize` enum
2. `WidgetType` enum
3. `WidgetItem` struct
4. `WidgetRow` struct
5. `MainScreenView` (the view)
6. `EntryRowView`
7. `WidgetCardView`
8. `NamePromptSheet`
9. `AddEntrySheet`
10. `EditEntrySheet`
11. `FlowLayout`
12. `WidgetDropDelegate`

This violates the Single File / Single Responsibility principle. Cross-cutting types (`WidgetItem`, `FlowLayout`) are trapped inside a view file.

**Recommendation:** Extract into separate files:

- `Models/WidgetItem.swift` for widget types
- `Views/EntryRowView.swift`, `Views/AddEntrySheet.swift`, `Views/EditEntrySheet.swift`
- `Layouts/FlowLayout.swift`

---

## 3. Data Governance & Privacy

### 3.1 No Data Classification Scheme

**Severity: CRITICAL** | **Category: Compliance**

The application processes the following data categories with no classification, no retention policy, and no documented data flow:

| Data | Classification (should be) | Current Protection |
|---|---|---|
| Journal entry text | PII / Sensitive Personal | None (plaintext SQLite) |
| Mood tracking | Special Category (health) | None (plaintext) |
| Tags / categories | Behavioral metadata | None |
| User name | PII | UserDefaults (plaintext) |
| Wallpaper image | Personal media | File system (no protection attr) |
| Notification schedule | Behavioral | UserDefaults (plaintext) |
| Goal data | Personal | None (plaintext SQLite) |

Under GDPR Article 9, mood tracking may constitute "data concerning health" — a special category requiring explicit consent and enhanced protections.

### 3.2 No Privacy Policy or Consent Flow

**Severity: CRITICAL** | **Category: Compliance**

Apple App Store Review Guidelines require a privacy policy. GDPR/CCPA require informed consent before processing personal data. The app has:

- No privacy policy URL
- No consent dialog at first launch
- No data processing transparency
- No right-to-erasure mechanism (bulk delete all data)
- No data portability beyond manual CSV/JSON export

### 3.3 No Data Retention or Purge Policy

**Severity: HIGH** | **Category: Governance**

Journal entries accumulate indefinitely. There is no:

- Configurable retention period
- Archive/purge mechanism
- Storage usage indicator
- Warning when local storage grows large

### 3.4 Export Contains All Data Without Consent Confirmation

**Severity: MEDIUM** | **Category: Privacy**

`SettingsView.swift:179-184` exports all entries with a single tap. No confirmation dialog, no data preview, no warning that sensitive mood/health data is included. The export file lands in a temp directory accessible until system cleanup.

---

## 4. Security Controls

### 4.1 No Authentication or Biometric Lock

**Severity: HIGH** | **Category: Security**

A journaling app containing personal reflections and mood/health data has no access protection. Anyone with physical device access can read all entries. Industry standard for health-adjacent apps is FaceID/TouchID or passcode lock.

### 4.2 No Data-at-Rest Encryption

**Severity: HIGH** | **Category: Security**

SwiftData stores to an unencrypted SQLite database. The `ModelConfiguration` does not specify any encryption options. The database can be extracted from device backups (unencrypted iTunes backups) or jailbroken devices.

`WallpaperStorage` writes with default file protection:

```swift
// SettingsView.swift:284
try? data.write(to: fileURL)  // No .completeFileProtection
```

### 4.3 CSV Formula Injection

**Severity: MEDIUM** | **Category: Security**

`DataExporter.swift:30` — Entry text starting with `=`, `+`, `-`, `@` will be interpreted as formulas by spreadsheet software. Only double-quote escaping is performed.

**Recommendation:** Prefix cell values that start with `=`, `+`, `-`, `@`, `\t`, or `\r` with a single quote or a tab character to prevent formula interpretation.

### 4.4 Predictable Export Filenames

**Severity: MEDIUM** | **Category: Security**

`DataExporter.swift:54,64` — Hardcoded filenames `journal_entries.csv` and `journal_entries.json` in the temp directory. Overwrites previous exports silently. No cleanup after share sheet dismissal.

**Recommendation:**

- Use a UUID-based or timestamped filename: `"journal_entries_\(UUID().uuidString).csv"`
- Delete the temp file after the share sheet is dismissed
- Consider using a subdirectory with restricted permissions

### 4.5 No Input Validation Framework

**Severity: MEDIUM** | **Category: Security**

Input validation is ad-hoc and inconsistent:

| Field | Validation | Gap |
|---|---|---|
| User name | Trimmed, non-empty check | No length limit, no character filter |
| Entry text | Trimmed, non-empty check | No length limit |
| Tag name | Trimmed, non-empty check | No length limit, no character filter |
| Goal title | Trimmed, non-empty check | No length limit |
| Duration slider | `1...120` range | Correct |
| Notification hour | `0..<24` via picker | Correct |
| Goal progress | `0...1` clamped in init | Correct, but Stepper binding bypasses init clamping |

**Note on Goal progress:** `GoalsDetailView.swift:81` binds the stepper directly to `$goal.progress` with range `0...1`, but since `Goal` is a `@Model` class, the `progress` property setter does not enforce clamping after initialization. The init clamps, but subsequent stepper mutations do not.

### 4.6 Notification Permission Error Not Communicated

**Severity: LOW** | **Category: UX/Security**

`SettingsView.swift:128-130` — If notification authorization is denied, the toggle silently reverts. No explanation, no link to Settings.app.

---

## 5. Testing & Quality Assurance

### 5.1 Test Coverage Is Narrow

**Severity: HIGH** | **Category: Quality**

**Current state:** 39 unit tests, 3 UI tests (all boilerplate), 0 integration tests.

**Coverage analysis:**

| Layer | Tested | Not Tested |
|---|---|---|
| `StreakCalculator` | 11 tests | Fully covered |
| `JournalEntry` model | 5 tests | SwiftData persistence not tested |
| `Goal` model | 2 tests | Progress setter bypass not tested |
| `Tag` model | 1 test | Uniqueness constraint not tested |
| `Mood` enum | 4 tests | Adequately covered |
| `DataExporter` | 7 tests | Formula injection not tested |
| `WidgetItem` codable | 2 tests | Adequately covered |
| `AccentColorChoice` | 2 tests | Trivial |
| `TextSizeChoice` | 2 tests | Trivial |
| `WallpaperStorage` | 1 test | Concurrent access not tested |
| `StorageKeys` | 1 test | Trivial |
| `NotificationManager` | 0 tests | **Untested** |
| All ViewModels | 0 tests | N/A — none exist |
| All Views | 0 tests | No snapshot/interaction tests |
| Navigation flows | 0 tests | No integration tests |
| Data migration | 0 tests | No schema version tests |

**Estimated line coverage: ~15-20%** (only pure utility/model code is tested; all view and coordinator logic is untested).

### 5.2 UI Tests Are Xcode Boilerplate

**Severity: MEDIUM** | **Category: Quality**

`JournalInsightUITests.swift` and `JournalInsightUITestsLaunchTests.swift` contain only the default Xcode template code. `testExample()` launches the app and does nothing. No user journey is automated.

**Critical untested flows:**

- Entry creation end-to-end
- Entry edit and delete
- Export generation and sharing
- Notification toggle with permission handling
- Widget drag-and-drop reorder

### 5.3 No Test Isolation for Date-Dependent Logic

**Severity: MEDIUM** | **Category: Quality**

`StreakCalculatorTests` uses `Date()` (wall clock) to construct test data. Tests will produce different results at different times of day, particularly around midnight. Tests using `entry(daysAgo: 0)` at 23:59 vs 00:01 may fail intermittently.

### 5.4 No Performance or Load Tests

**Severity: LOW** | **Category: Quality**

No tests verify behavior with large data sets. Several views iterate over all entries in computed properties (e.g., `SessionDetailView` chart data, `CalendarDetailView` day filtering). With thousands of entries, these O(n) iterations per frame could degrade UI performance.

---

## 6. Documentation Gaps

### 6.1 Missing Documentation Inventory

| Document | Status | Priority |
|---|---|---|
| Architecture Decision Records (ADRs) | Missing | HIGH |
| C4 Architecture Diagrams | Missing | HIGH |
| Data Flow Diagrams | Missing | HIGH |
| Swimlane Diagrams (user journeys) | Missing | HIGH |
| Entity Relationship Diagram | Missing | MEDIUM |
| Privacy Policy | Missing | CRITICAL |
| Data Processing Impact Assessment (DPIA) | Missing | HIGH (if targeting EU) |
| API / Module Contracts | Missing | MEDIUM |
| Threat Model (STRIDE) | Missing | MEDIUM |
| Runbook / Operational Procedures | Missing | LOW |
| Accessibility Conformance Report | Missing | MEDIUM |
| Localization Strategy | Missing | LOW |
| Error Handling Strategy | Missing | MEDIUM |
| Branching & Release Strategy | Missing | MEDIUM |
| Code Style Guide | Partially in CLAUDE.md | LOW |
| Onboarding / Developer Guide | Missing | MEDIUM |

### 6.2 CLAUDE.md Is Not a Substitute for Architecture Documentation

**Severity: MEDIUM** | **Category: Governance**

`CLAUDE.md` is an AI session log, not an architecture document. It records what changed but not why decisions were made, what alternatives were considered, or what constraints apply. It is not useful for onboarding a new developer or conducting a design review.

### 6.3 No Inline Documentation on Public Interfaces

**Severity: LOW** | **Category: Maintainability**

Only `StreakCalculator.swift` has doc comments (3 `///` comments). No other public type, method, or property in the codebase has documentation. SwiftData model relationships, computed properties with business logic, and enum semantics are all undocumented.

---

## 7. Operational Risk

### 7.1 No Error Handling Strategy

**Severity: HIGH** | **Category: Resilience**

The codebase uses `try?` in every error-producing call (14 occurrences across 4 files). Errors are never logged, never surfaced, never tracked. If SwiftData fails to save, the user loses data silently.

**Specific instances:**

- `DataExporter.swift:56,68` — file write failures silently return nil
- `SettingsView.swift:206,284` — photo load / wallpaper save failures silent
- `NotificationManager.swift:16` — authorization error discarded
- `MainScreenView.swift:574` — timer sleep error discarded

### 7.2 No Logging Framework

**Severity: MEDIUM** | **Category: Observability**

Zero use of `os.Logger`, `print()` for debugging, or any structured logging. In production, there is no way to diagnose user-reported issues.

### 7.3 No Crash Reporting or Analytics

**Severity: MEDIUM** | **Category: Observability**

No integration with crash reporting (e.g., Firebase Crashlytics, Sentry) or analytics. The development team has no visibility into production failures.

### 7.4 No SwiftData Schema Migration Strategy

**Severity: HIGH** | **Category: Resilience**

The data models have already undergone significant changes (struct to class, added mood, tags). SwiftData handles lightweight migrations automatically, but there is:

- No `VersionedSchema` or `SchemaMigrationPlan`
- No migration tests
- No documented schema version history
- No protection against data loss during migration

If a future schema change is non-trivial (e.g., splitting `JournalEntry` into normalized tables), the lack of explicit migration handling will cause data loss.

### 7.5 No Backup / Restore Capability

**Severity: MEDIUM** | **Category: Resilience**

Beyond CSV/JSON export, there is no way to back up and restore the full database (including tags, goals, and relationships). The export format is lossy — it does not include entry IDs, tag relationships, or goal data.

---

## 8. Code Quality Findings

### 8.1 Duplicated Mood Picker UI

**Severity: LOW** | **Category: DRY**

The mood emoji picker (HStack of mood buttons) is duplicated verbatim in three locations:

- `MainScreenView.swift:431-448` (AddEntrySheet)
- `MainScreenView.swift:613-630` (EditEntrySheet)
- `QuestionsDetailView.swift:86-103`

**Recommendation:** Extract a `MoodPicker` reusable view component.

### 8.2 Duplicated Tag Picker UI

**Severity: LOW** | **Category: DRY**

The tag flow layout + "New tag" field is duplicated identically in:

- `MainScreenView.swift:491-529` (AddEntrySheet)
- `MainScreenView.swift:647-684` (EditEntrySheet)

**Recommendation:** Extract a `TagPicker` reusable view component.

### 8.3 DispatchQueue.main.async Inside SwiftUI

**Severity: LOW** | **Category: Correctness**

`MainScreenView.swift:257` — The `WidgetDropDelegate` uses `DispatchQueue.main.async` for state mutation. In SwiftUI, `@State` mutations should happen on the main actor, and `NSItemProvider` callbacks are not guaranteed to be main-thread. The correct modern approach is `@MainActor` annotation or `Task { @MainActor in }`.

### 8.4 Computed Properties Recalculate Every Render

**Severity: MEDIUM** | **Category: Performance**

`CalendarDetailView.swift:108` — Inside a `LazyVGrid` `ForEach`, `entries.filter { Calendar.current.isDate(...) }` is called per calendar cell per render. For month view (28-31 cells) with N entries, this is O(cells * N) per frame.

Similar pattern in `SessionDetailView.swift:37-57` — chart data recomputes O(7 * N) per render.

**Recommendation:** Cache filtered results in `@State` or a ViewModel, updated only when `entries` changes.

---

## 9. Accessibility

### 9.1 No Accessibility Audit Performed

**Severity: MEDIUM** | **Category: Compliance**

No `accessibilityLabel`, `accessibilityHint`, or `accessibilityValue` modifiers are used anywhere in the codebase. Mood emojis (`EntryRowView`, calendar dots) will be read as raw Unicode by VoiceOver, not as meaningful labels like "Mood: Great".

Widget cards, entry rows, and chart elements have no accessibility annotations.

---

## 10. Recommendations Matrix

### Priority 1 — Must Fix (Pre-Release Blockers)

| # | Finding | Section | Effort |
|---|---|---|---|
| R1 | Create and publish a Privacy Policy | 3.2 | Low |
| R2 | Add biometric/passcode lock option | 4.1 | Medium |
| R3 | Enable `NSFileProtectionComplete` on data files | 4.2 | Low |
| R4 | Add data export consent confirmation dialog | 3.4 | Low |
| R5 | Sanitize CSV export against formula injection | 4.3 | Low |
| R6 | Add SwiftData `VersionedSchema` and migration plan | 7.4 | Medium |

### Priority 2 — Should Fix (Next Sprint)

| # | Finding | Section | Effort |
|---|---|---|---|
| R7 | Adopt MVVM with extracted ViewModels | 2.1 | High |
| R8 | Extract reusable components (MoodPicker, TagPicker) | 8.1, 8.2 | Low |
| R9 | Add input length validation (name, tags, entry text) | 4.5 | Low |
| R10 | Replace `try?` with proper error handling + logging | 7.1 | Medium |
| R11 | Add `os.Logger` structured logging | 7.2 | Low |
| R12 | Use UUID-based temp filenames and cleanup after share | 4.4 | Low |
| R13 | Increase unit test coverage to >60% | 5.1 | High |
| R14 | Write real UI tests for critical flows | 5.2 | Medium |
| R15 | Add accessibility labels to all interactive elements | 9.1 | Medium |

### Priority 3 — Should Plan (Roadmap)

| # | Finding | Section | Effort |
|---|---|---|---|
| R16 | Create C4 architecture diagrams | 6.1 | Medium |
| R17 | Create swimlane diagrams for entry creation, export, notification setup | 6.1 | Medium |
| R18 | Create Entity Relationship Diagram for SwiftData models | 6.1 | Low |
| R19 | Document STRIDE threat model | 6.1 | Medium |
| R20 | Add data retention / purge settings | 3.3 | Medium |
| R21 | Add full backup/restore capability | 7.5 | High |
| R22 | Integrate crash reporting (Sentry/Crashlytics) | 7.3 | Low |
| R23 | Performance test with 10,000+ entries | 5.4 | Medium |
| R24 | Add DPIA if targeting EU market | 3.2 | Medium |
| R25 | Break up `MainScreenView.swift` into <300 line files | 2.4 | Medium |
| R26 | Inject `Clock` protocol for deterministic date testing | 2.2 | Medium |

---

## 11. Summary of Deliverables Owed

The following documents and artifacts do not exist and should be created:

1. **Privacy Policy** — Legal document, required for App Store submission
2. **Architecture Decision Records** — ADR-001: Pattern choice, ADR-002: Persistence, ADR-003: Data classification
3. **C4 Diagrams** — Context, Container, Component levels
4. **Swimlane Diagrams** — Entry CRUD flow, Export flow, Notification setup flow
5. **Entity Relationship Diagram** — JournalEntry, Tag, Goal relationships
6. **Data Flow Diagram** — SwiftData, Views, UserDefaults, File System interactions
7. **STRIDE Threat Model** — Spoofing, Tampering, Repudiation, Info Disclosure, DoS, Elevation
8. **Test Plan** — Coverage targets, test pyramid strategy, CI pipeline requirements
9. **Schema Migration Plan** — Versioned schemas, migration test matrix
10. **Accessibility Conformance Report** — WCAG 2.1 AA mapping
11. **Error Handling Strategy** — Classification, logging levels, user-facing messaging
12. **Release & Branching Strategy** — GitFlow/trunk-based, versioning scheme, release checklist

---

## Appendix A: Files Reviewed

| File | Lines | Role |
|---|---|---|
| `AppTheme.swift` | 81 | Theme constants, shared enums, storage keys |
| `JournalEntry.swift` | 67 | JournalEntry @Model, Tag @Model, Mood enum |
| `Goal.swift` | 23 | Goal @Model |
| `StreakCalculator.swift` | 67 | Business logic — streak computation |
| `NotificationManager.swift` | 46 | UNUserNotificationCenter wrapper |
| `DataExporter.swift` | 73 | CSV/JSON export utilities |
| `JournalInsightApp.swift` | 28 | App entry point, model container |
| `MainScreenView.swift` | 762 | Main dashboard, widgets, entry CRUD, timer, tags |
| `CalendarDetailView.swift` | 252 | Calendar with month navigation |
| `SettingsView.swift` | 332 | Settings, notifications, export, wallpaper |
| `StreakDetailView.swift` | 198 | Streak stats and milestones |
| `SessionDetailView.swift` | 197 | Session KPIs with Swift Charts |
| `QuestionsDetailView.swift` | 143 | Journaling prompts |
| `GoalsDetailView.swift` | 140 | Goal CRUD |
| `JournalInsightTests.swift` | 385 | 39 unit tests across 12 suites |
| `JournalInsightUITests.swift` | 42 | Boilerplate UI test (no real assertions) |
| `JournalInsightUITestsLaunchTests.swift` | 34 | Boilerplate launch test |

**Total source lines:** ~2,870 (excluding tests)
**Total test lines:** ~461

## Appendix B: Positive Findings

The following areas were found to be satisfactory:

| Area | Assessment |
|---|---|
| No network requests | App is fully offline. No MITM, API key exposure, or server-side risk. |
| No web views | No WKWebView or SFSafariViewController. No XSS risk. |
| No SQL injection surface | SwiftData uses parameterized queries internally. |
| No third-party dependencies | Zero CocoaPods, SPM, or framework dependencies. Zero supply-chain risk. |
| Input trimming | Whitespace is trimmed before saving names, entries, and goals. |
| Delete confirmation | Destructive actions (entry delete, wallpaper remove) require user confirmation. |
| DST-safe date calculations | Calendar logic uses proper Calendar APIs, not raw second arithmetic. |
| Static DateFormatter allocation | Formatters are `static let`, avoiding repeated allocation per frame. |
| Stable SwiftUI identity | Widget rows use content-derived IDs, not `UUID()` in computed properties. |
| Extracted testable logic | `StreakCalculator` is a pure function utility, fully unit tested. |

---

*This report represents the findings at the time of review. Remediation should be prioritized according to the matrix in Section 10 and tracked in a formal issue tracker with assigned owners and due dates.*
