import SwiftUI

/// DESIGN-6 / rule 5: shared copy for a value that exists conceptually but isn't computable
/// from the current data source — never a bare "—" with a dangling unit. Shared by
/// `StatChip`, `ReadinessArcGauge`, `DriverBars`, and this file's `EAGatedTile`.
public nonisolated let sourceMissingCopy = "Not from the current source"

/// The "energy availability not computable" gated-tile idiom (W2 spec §8): a tile whose
/// value cannot be derived from the current source at all (as opposed to `StatChip`'s
/// `sourceMissing`, which still shows a numeral-shaped placeholder). Renders a clearly
/// gated/unavailable state with honest copy — never a zero, never a bare dash.
public struct EAGatedTile: View {
    let label: String
    let reason: String
    @Environment(\.jiTheme) private var theme

    public init(label: String, reason: String = sourceMissingCopy) {
        self.label = label
        self.reason = reason
    }

    public var body: some View {
        Surface(level: 2, padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.caption).foregroundStyle(theme.color(.muted)).lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(theme.color(.muted))
                    Text(reason).font(.footnote).foregroundStyle(theme.color(.muted))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(eaGatedTileAccessibilityLabel(label: label, reason: reason))
    }
}

/// Pure, testable label builder — mirrors what `StatChip`/`ReadinessArcGauge` announce for
/// their own source-missing state, so the gated idiom reads consistently across tiles.
public nonisolated func eaGatedTileAccessibilityLabel(label: String, reason: String) -> String {
    "\(label), \(reason)"
}
