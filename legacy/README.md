# legacy/ — the 2025–2026 SwiftUI/SwiftData JournalInsight (read-only donor)

Moved here 2026-09-12 (spec: HealthTraining/docs/superpowers/specs/2026-09-12-ji-swift-native-migration-design.md, decision #10).
Not built by the new project. Lift by file, never by target:
- HealthKit/HealthKitObserver.swift, HealthKitReader.swift, HealthKitPermissions.swift (main 641142e) → W2 JIHealthKit
- StreakCalculator.swift, CalendarGrid.swift, CalendarDetailView.swift → W4 Journal
- Vault/* lives on worktree commit 4b012de, not here: `git show 4b012de:JournalInsight/Vault/<file>` → W4 JIVault
