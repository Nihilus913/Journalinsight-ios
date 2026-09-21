import SwiftUI
import JIDesign

/// Entry point for the JournalInsight watch app: three swipeable glances —
/// verdict, readiness, My KPIs — read-only against the App-Group snapshot
/// (`WatchSnapshotStore`). No hub calls, no token, this wave (P-watch).
@main
struct WatchApp: App {
    @StateObject private var snapshotStore = WatchSnapshotStore()
    // Launch-argument seam for `docs/DEVICE_RECORDING_PROTOCOL_IOS.md`-style captures and
    // this wave's close-out screenshots: `WATCH_GLANCE_TAB=1` opens straight to a given
    // glance instead of always starting on the verdict page.
    @State private var watchGlanceDebugSelection = Int(
        ProcessInfo.processInfo.environment["WATCH_GLANCE_TAB"] ?? ""
    ) ?? 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: $watchGlanceDebugSelection) {
                VerdictGlance(snapshot: snapshotStore.snapshot)
                    .containerBackground(JITheme.native.color(.bg), for: .tabView)
                    .tag(0)
                ReadinessGlance(snapshot: snapshotStore.snapshot)
                    .containerBackground(JITheme.native.color(.bg), for: .tabView)
                    .tag(1)
                MyKpisGlance(snapshot: snapshotStore.snapshot)
                    .containerBackground(JITheme.native.color(.bg), for: .tabView)
                    .tag(2)
            }
            .tabViewStyle(.verticalPage)
            // B-33: the whole watch app ships in the native language (spec §1 — watchOS has no
            // UIKit semantic colours, so JINativePalette's watch branch supplies them).
            .jiTheme(.native)
            .task { snapshotStore.refresh() }
            .onAppear { snapshotStore.refresh() }
        }
    }
}
