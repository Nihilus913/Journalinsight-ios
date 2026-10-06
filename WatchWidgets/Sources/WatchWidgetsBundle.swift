import SwiftUI
import WidgetKit

/// W-BUG1 BUG1-3 (B-130): the watchOS widget extension that actually registers
/// `VerdictComplication` with the system. Before this target the complication type compiled into
/// the watch APP only, so no watch face could offer it and W-B78's `WidgetCenter` reload had
/// nothing to reach. The extension reads the snapshot the watch app stores on receive
/// (`WatchSnapshotStore.apply` → watch-local App Group), never the network.
@main
struct WatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        VerdictComplication()
    }
}
