import WidgetKit
import SwiftUI

/// Widget + Live Activity bundle for the JournalInsight extension.
/// L3 (P-widgets, P-live-activity): `GateWidget`, `KpiWidget` render from the
/// App-Group `HubSnapshot` (no network); `VerdictLiveActivity` is local-start
/// only, driven by `LiveActivityController` (App-side callers in W2c-L1).
@main
struct WidgetsBundle: WidgetBundle {
    var body: some Widget {
        GateWidget()
        KpiWidget()
        VerdictLiveActivity()
    }
}
