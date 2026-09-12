import Foundation
import BackgroundTasks

// Identifier must match BGTaskSchedulerPermittedIdentifiers in Info.plist (added in SP4 when Garmin sync arrives).
let kBGSyncTaskIdentifier = "com.journalinsight.backgroundSync"

// SP2: scaffolding only. Real registration happens in SP4 when Garmin sync provides actual work
// for the background slot. Registering an empty handler in SP2 would waste BGTask budget allocation.
enum BackgroundSyncManager {

    /// SP2 no-op. Implemented in SP4 once Garmin sync is wired up.
    static func registerTasks() {
        // Intentionally empty. See file header comment.
    }

    /// SP2 no-op. Implemented in SP4 once Garmin sync is wired up.
    static func scheduleNext() {
        // Intentionally empty. See file header comment.
    }
}
