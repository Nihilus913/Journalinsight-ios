import Foundation
import JISnapshot

/// App-Group suite the App/Widgets/WatchApp targets all share (see
/// `App/JournalInsight.entitlements`, `WatchApp/WatchApp.entitlements`).
public nonisolated let watchAppGroupSuite = "group.toby913.JournalInsight"

/// Watch-side wrapper around `JISnapshot.SnapshotStore`: reads the latest
/// `HubSnapshot` written by the phone app and republishes it to SwiftUI via
/// `@Published`, so the three glances redraw when a new snapshot lands.
///
/// The watch app never talks to the hub directly this wave (P-watch is
/// read-only against the App-Group store) — it has no token to talk with,
/// by construction (`HubSnapshot` excludes it; see JISnapshot/HubSnapshot.swift).
@MainActor
public final class WatchSnapshotStore: ObservableObject {
    @Published public private(set) var snapshot: HubSnapshot?

    private let store: SnapshotStore

    public init(suiteName: String = watchAppGroupSuite) {
        self.store = SnapshotStore(suiteName: suiteName)
        self.snapshot = store.read()
    }

    /// Re-reads the App-Group store. Cheap (UserDefaults), safe to call from
    /// `.onAppear` / `.task` / a periodic complication-adjacent refresh.
    public func refresh() {
        snapshot = store.read()
    }
}
