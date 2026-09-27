import SwiftUI

/// A single named driver contributing to readiness. `value` is a normalized magnitude in
/// `0...1`; `sourceMissing` follows the same convention as `StatChip`/`ReadinessArcGauge`.
/// B-57 W3: `nonisolated` so its `Equatable` conformance is usable from pure nonisolated models
/// (`RecoveryCardModel`) — it is plain data, no MainActor state.
public nonisolated struct DriverBar: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let value: Double?
    public let sourceMissing: Bool
    /// B-57 W3: optional status word shown right of the label ("Low", "In your normal",
    /// "Above goal", "Calibrating", "No reading") and read by VoiceOver instead of the percent.
    public let word: String?
    /// B-57 W3: optional status tint for the fill (`.reduced` = low, `.sleep`). `.go` is ignored
    /// (rule 6 — verdict green is never a driver colour).
    public let tint: JIColorRole?

    // nonisolated: DriverBar is a pure data type (like ReadinessContributor in
    // ContributorBreakdown.swift) constructed from JIDesignTests' nonisolated `@Test` funcs
    // (SourceMissingCopyTests.swift, DriverBarsTests.swift) — it must stay callable outside
    // JIDesign's MainActor default isolation despite touching no MainActor-isolated state.
    public nonisolated init(id: String, label: String, value: Double?, sourceMissing: Bool = false,
                            word: String? = nil, tint: JIColorRole? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.sourceMissing = sourceMissing
        self.word = word
        self.tint = tint
    }
}

/// Readiness driver bars (W2 spec §8). Rule 6: these are contributor/component bars, so they
/// are **always neutral gray** (`mutedNested`) — never the reserved verdict green — regardless
/// of how large a driver's contribution is. Rule 5: a missing driver announces the shared
/// source-missing copy rather than drawing a zero-width bar with no explanation.
public struct DriverBars: View {
    let drivers: [DriverBar]
    @Environment(\.jiTheme) private var theme

    public init(drivers: [DriverBar]) {
        self.drivers = drivers
    }

    /// Never the reserved verdict green (`.go`) — driver bars are neutral, always. A ROLE, not a
    /// `Color`: the active theme resolves it in `body` (B-33 Phase C).
    nonisolated static let barRole: JIColorRole = .mutedNested

    /// B-57 W3: a status tint is allowed (amber `.reduced` = low, metric `.sleep`), the verdict
    /// green never is (rule 6) — `.go` falls back to the neutral bar.
    nonisolated static func fillRole(for driver: DriverBar) -> JIColorRole {
        guard let tint = driver.tint, tint != .go else { return barRole }
        return tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(drivers) { driver in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(driver.label).font(.caption).foregroundStyle(theme.color(.muted)).lineLimit(1)
                        Spacer(minLength: 8)
                        if let word = driver.word {
                            Text(word).font(.caption.weight(.semibold))
                                .foregroundStyle(theme.color(driver.value == nil ? .muted : Self.fillRole(for: driver)))
                                .lineLimit(1)
                        }
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.color(.surface3)).frame(height: 6)
                            if !driver.sourceMissing, let value = driver.value {
                                Capsule()
                                    .fill(theme.color(Self.fillRole(for: driver)))
                                    .frame(width: g.size.width * CGFloat(min(max(value, 0), 1)), height: 6)
                            }
                        }
                    }.frame(height: 6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(driverBarAccessibilityLabel(driver: driver))
            }
        }
    }
}

/// Pure, testable label builder (rule 5 + DESIGN-6): mirrors the source-missing copy used by
/// `StatChip`/`ReadinessArcGauge`/`EAGatedTile` so every tile announces it identically.
public nonisolated func driverBarAccessibilityLabel(driver: DriverBar) -> String {
    if driver.sourceMissing { return "\(driver.label) \(sourceMissingCopy)" }
    if let word = driver.word { return "\(driver.label), \(word)" }
    guard let value = driver.value else { return "\(driver.label), no data yet" }
    return "\(driver.label) \(Int((value * 100).rounded()))%"
}
