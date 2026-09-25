import SwiftUI

/// "your normal 27–30" > "goal 155 g" > caller detail (W1: the hub threshold, e.g. "floor 7.0 h").
public nonisolated func signalReferenceText(normal: ClosedRange<Double>?, goal: Double?, unit: String?, decimals: Int, detail: String?) -> String? {
    if let normal { return "your normal \(jiNumber(normal.lowerBound, decimals))–\(jiNumber(normal.upperBound, decimals))" }
    if let goal {
        let u = (unit?.isEmpty == false) ? " \(unit!)" : ""
        return "goal \(jiNumber(goal, decimals))\(u)"
    }
    return detail
}

public nonisolated func signalRowAccessibilityLabel(label: String, value: Double?, unit: String?, decimals: Int, status: JISignalStatus, reference: String?) -> String {
    let u = (unit?.isEmpty == false) ? " \(unit!)" : ""
    return [label, value.map { "\(jiNumber($0, decimals))\(u)" } ?? "no value", status.word, reference]
        .compactMap { $0 }.joined(separator: ", ")
}

/// B-57 §1 (replaces the old gate-signal arcs row, B-72): label + reference line on the left, value and the
/// tinted, worded status on the right. Stacks at AX sizes and always keeps its full height.
public struct SignalRow: View {
    let label: String, value: Double?, unit: String?, decimals: Int
    let normal: ClosedRange<Double>?, goal: Double?, status: JISignalStatus, detail: String?
    @Environment(\.jiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(label: String, value: Double?, unit: String? = nil, decimals: Int = 0, normal: ClosedRange<Double>? = nil,
                goal: Double? = nil, status: JISignalStatus, detail: String? = nil) {
        self.label = label; self.value = value; self.unit = unit; self.decimals = decimals
        self.normal = normal; self.goal = goal; self.status = status; self.detail = detail
    }

    private var reference: String? { signalReferenceText(normal: normal, goal: goal, unit: unit, decimals: decimals, detail: detail) }

    public var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                if let reference { Text(reference).jiFont(.footnote).foregroundStyle(theme.color(.muted)) }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(jiValueText(value, decimals: decimals)).jiFont(.body, weight: .bold)
                        .foregroundStyle(theme.color(value == nil ? .muted : .text))
                    if value != nil, let unit, !unit.isEmpty { Text(unit).jiFont(.caption).foregroundStyle(theme.color(.muted)) }
                }
                Label(status.word, systemImage: status.symbolName)
                    .jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(status.role))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        // W-B57-W1 verifier (AX3): never squeezed below its own height by a height-starved parent —
        // a squeezed row drew its lines over the next row. It grows; the container scrolls.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(signalRowAccessibilityLabel(label: label, value: value, unit: unit, decimals: decimals, status: status, reference: reference))
    }
}
