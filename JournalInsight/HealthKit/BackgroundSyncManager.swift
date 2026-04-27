import Foundation
import BackgroundTasks

// Identifier must match BGTaskSchedulerPermittedIdentifiers in Info.plist
let kBGSyncTaskIdentifier = "com.journalinsight.backgroundSync"

enum BackgroundSyncManager {

    // Call from application(_:didFinishLaunchingWithOptions:) or @main init
    static func registerTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: kBGSyncTaskIdentifier, using: nil) { task in
            handleSync(task: task as! BGAppRefreshTask)
        }
    }

    // Schedule next background refresh — call after every sync completes
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: kBGSyncTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)  // at least 1 hour out
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleSync(task: BGAppRefreshTask) {
        scheduleNext()
        task.expirationHandler = { task.setTaskCompleted(success: false) }
        // SP2 only: observer handles new workouts reactively. Garmin sync arrives in SP4.
        task.setTaskCompleted(success: true)
    }
}
