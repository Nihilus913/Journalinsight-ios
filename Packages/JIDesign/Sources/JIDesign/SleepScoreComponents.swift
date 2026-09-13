import SwiftUI

/// One sub-component of the sleep score (e.g. "Duration", "Consistency", "Deep sleep").
public struct SleepScoreComponent: Identifiable, Equatable, Sendable {
    public let id: String, label: String, value: Double?
    public init(id: String, label: String, value: Double?) { self.id = id; self.label = label; self.value = value }
}

/// Sub-bars for the sleep-score components. These are component/contributor bars, not the
/// score/band itself — NEUTRAL (`mutedNested`) always, never the reserved verdict green.
public struct SleepScoreComponents: View {
    let components: [SleepScoreComponent], sourceMissing: Bool
    public init(components: [SleepScoreComponent], sourceMissing: Bool = false) {
        self.components = components; self.sourceMissing = sourceMissing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(components) { component in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(component.label).font(.caption).foregroundStyle(JIColor.muted)
                        Spacer()
                        Text(valueText(component.value)).font(.caption).foregroundStyle(JIColor.text)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(JIColor.surface3)
                            if let value = component.value, !sourceMissing {
                                Capsule().fill(JIColor.mutedNested)
                                    .frame(width: g.size.width * CGFloat(min(max(value, 0), 100) / 100))
                            }
                        }
                    }.frame(height: 6)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(component.label) \(sourceMissing ? "Not from the current source" : valueText(component.value))")
            }
        }
    }

    private func valueText(_ value: Double?) -> String {
        guard !sourceMissing, let value else { return sourceMissing ? "Not from the current source" : "—" }
        return value.formatted(.number.precision(.fractionLength(0)))
    }
}
