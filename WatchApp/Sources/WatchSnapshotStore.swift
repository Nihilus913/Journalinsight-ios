import Foundation
import JISnapshot
#if canImport(WidgetKit)
import WidgetKit
#endif

/// App-Group suite the App/Widgets/WatchApp targets all share (see
/// `App/JournalInsight.entitlements`, `WatchApp/WatchApp.entitlements`).
public nonisolated let watchAppGroupSuite = "group.toby913.JournalInsight"

/// Watch-side snapshot source for the three glances (+ VerdictComplication), republished to
/// SwiftUI via `@Published`.
///
/// W-B78 (B-78): a real watch has no access to the phone's App Group, so the phone pushes the
/// `HubSnapshot` over WatchConnectivity (`SnapshotWire`, application context). `apply(_:)` decodes
/// it, persists it to WATCH-LOCAL defaults (`UserDefaults.standard`, never the App Group) so an
/// offline relaunch shows the last copy, publishes it, and reloads the complication timelines.
/// The App-Group store stays as a read fallback (simulator / pre-B-78 path).
///
/// The watch never talks to the hub — it has no token, by construction (`HubSnapshot` excludes it).
@MainActor
public final class WatchSnapshotStore: ObservableObject {
    @Published public private(set) var snapshot: HubSnapshot?

    private let store: SnapshotStore
    private let local: SnapshotStore
    private let reloadTimelines: () -> Void

    public init(
        suiteName: String = watchAppGroupSuite,
        local: UserDefaults = .standard,
        reloadTimelines: @escaping () -> Void = WatchSnapshotStore.reloadAllTimelines
    ) {
        self.store = SnapshotStore(suiteName: suiteName)
        self.local = SnapshotStore(defaults: local)
        self.reloadTimelines = reloadTimelines
        self.snapshot = Self.read(local: self.local, group: store)
    }

    /// Re-reads the stored copies (watch-local wire copy first, then the App Group). Cheap.
    public func refresh() {
        snapshot = Self.read(local: local, group: store)
    }

    /// W-B78: wire bytes from the phone (`SnapshotWire`). Garbage is ignored (returns false) and
    /// never replaces the last good copy.
    @discardableResult
    public func apply(_ data: Data) -> Bool {
        guard let received = SnapshotWire.decode(data) else { return false }
        local.write(received)
        // W-BUG1 BUG1-3 (B-130): the complication runs in the WatchWidgets extension — another
        // process with its own `.standard` defaults. On the watch the App Group container is
        // watch-local and shared by the watch app + its extension, so mirror the copy there.
        store.write(received)
        snapshot = received
        reloadTimelines()
        return true
    }

    /// A received application context (live delivery or `receivedApplicationContext` at activation).
    @discardableResult
    public func apply(context: [String: Any]) -> Bool {
        guard let data = context[SnapshotWire.key] as? Data else { return false }
        return apply(data)
    }

    nonisolated static func read(local: SnapshotStore, group: SnapshotStore) -> HubSnapshot? {
        local.read() ?? group.read()
    }

    public nonisolated static func reloadAllTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// DEBUG launch seam (`WATCH_FAKE_SNAPSHOT=1`): wire bytes of a fixed snapshot, fed through
    /// `apply(_:)` at launch so glance screenshots exercise the real receive path without a phone.
    public nonisolated static func debugFakeSnapshotData(environment: [String: String]) -> Data? {
        guard environment["WATCH_FAKE_SNAPSHOT"] == "1" else { return nil }
        let now = Date()
        let fake = HubSnapshot(
            verdictWord: "GO",
            verdictSession: "Full-upper session",
            verdictTone: "go",
            verdictDate: nil,
            readiness: 82,
            kpis: [
                SnapshotKPI(label: "HRV", value: 61, unit: "ms"),
                SnapshotKPI(label: "RHR", value: 48, unit: "bpm"),
                SnapshotKPI(label: "Sleep", value: 7.4, unit: "h"),
            ],
            fetchedAt: now,
            lastSync: now
        )
        return try? SnapshotWire.encode(fake)
    }
}
