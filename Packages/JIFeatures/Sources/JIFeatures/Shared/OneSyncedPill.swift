import SwiftUI
import JIDesign

// W-FIX4 L2 (PF-04): one sync-pill rule for every screen — the newer of the hub's last sync
// (`/ingestion/status` `last_sync`) and this app's last 2xx HealthKit upload, exactly what the
// Day pill shows since W-FIX2 (`TodayViewModel.syncedAt`). Never the moment a screen fetched.

extension EnvironmentValues {
    /// The shell's one sync instant (`TodayViewModel.syncedAt`), injected by `RootTabView` on
    /// every tab stack. `nil` when the shell has not wired it or knows neither time.
    @Entry public var jiSyncedAt: Date? = nil
}

/// The pill's instant: the newer of the injected shell value and the uploader's own record.
/// `nil` ("Not synced yet") when neither is known.
public nonisolated func oneSyncPillDate(injected: Date?, lastUpload: Date?) -> Date? {
    [injected, lastUpload].compactMap { $0 }.max()
}

/// `SyncedPill` fed by the one rule. The uploader's `hk.upload.lastSuccess` (App Group) is read
/// here too, so a screen still honours half the rule before the shell has injected the hub time.
public struct OneSyncedPill: View {
    @Environment(\.jiSyncedAt) private var injected
    private let label: JISyncedLabel
    private let uploadRecord: UserDefaults?

    public init(label: JISyncedLabel = .synced,
                uploadRecord: UserDefaults? = UserDefaults(suiteName: "group.toby913.JournalInsight")) {
        self.label = label; self.uploadRecord = uploadRecord
    }

    public var body: some View {
        SyncedPill(date: oneSyncPillDate(injected: injected,
                                         lastUpload: parseHubTimestamp(uploadRecord?.string(forKey: "hk.upload.lastSuccess"))),
                   label: label)
    }
}
