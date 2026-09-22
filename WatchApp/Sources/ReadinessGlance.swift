import SwiftUI
#if os(watchOS)
import WatchKit
#endif
import JIDesign
import JISnapshot

/// Second glance: readiness score via the shared `ReadinessArcGauge`
/// (JIDesign/ReadinessArcGauge.swift), sized for the watch face. `readiness
/// == nil` renders the gauge's own "No data yet" state — never a 0.
public struct ReadinessGlance: View {
    let snapshot: HubSnapshot?
    @Environment(\.jiTheme) private var theme
    public init(snapshot: HubSnapshot?) { self.snapshot = snapshot }

    /// §8.4: the arc is sized from the smaller side of the watch's own screen (≈0.55 ×), so a
    /// 42 mm face and an Ultra 4 render the same composition instead of a hard-coded 150 pt that
    /// overflows the small one and floats on the large one.
    public var body: some View {
        VStack(spacing: 4) {
            ReadinessArcGauge(score: snapshot?.readiness, size: ReadinessGlance.arcSize())
            if let lastSync = snapshot?.lastSync {
                Text(lastSync, style: .relative).jiFont(.micro).foregroundStyle(theme.color(.muted))
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 0.55 × the smaller side of `WKInterfaceDevice.screenBounds` (spec §8.4). The fallback keeps
    /// previews and the host-test target — where there is no `WKInterfaceDevice` — renderable.
    static func arcSize(fallback: CGFloat = 150) -> CGFloat {
        #if os(watchOS)
        let bounds = WKInterfaceDevice.current().screenBounds
        let smaller = Swift.min(bounds.width, bounds.height)
        guard smaller > 0 else { return fallback }
        return (smaller * 0.55).rounded()
        #else
        return fallback
        #endif
    }
}
