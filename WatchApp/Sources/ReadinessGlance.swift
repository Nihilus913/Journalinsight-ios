import SwiftUI
import JIDesign
import JISnapshot

/// Second glance: readiness score via the shared `ReadinessArcGauge`
/// (JIDesign/ReadinessArcGauge.swift), sized for the watch face. `readiness
/// == nil` renders the gauge's own "No data yet" state — never a 0.
public struct ReadinessGlance: View {
    let snapshot: HubSnapshot?
    public init(snapshot: HubSnapshot?) { self.snapshot = snapshot }

    public var body: some View {
        VStack(spacing: 4) {
            ReadinessArcGauge(score: snapshot?.readiness, size: 150)
            if let lastSync = snapshot?.lastSync {
                Text(lastSync, style: .relative).font(.caption2).foregroundStyle(JIColor.muted)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
