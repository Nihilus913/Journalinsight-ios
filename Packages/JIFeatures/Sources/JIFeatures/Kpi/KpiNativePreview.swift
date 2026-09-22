import SwiftUI
import JICore
import JIDesign

/// §8.5 registry entries "KPIs" and "KPI detail". Both compose the shipping components
/// (`KpiSelectionRow`, `KpiTargetsMirrorSection`, `TrendChart`) over fixtures — the sweep never
/// builds a hub-backed view model, whose `.task` `ImageRenderer` would not run anyway.
private nonisolated enum L5KpiFixtures {
    static let rows: [(label: String, value: String, target: String?)] = [
        ("HRV (7d avg)", "52 ms", "≥ 48"),
        ("Resting HR", "54 bpm", "≤ 58"),
        ("Sleep score (7d)", "81", "≥ 75"),
        ("ACWR", "1.08", "0.8–1.3"),
        ("Protein (7d avg)", "168 g", "≥ 160"),
        ("Weight", "104.2 kg", "≤ 100"),
    ]

    static let targets: [KpiTarget] = [
        KpiTarget(targetId: 1, metric: "hrv_weekly_avg", operator: ">=", threshold: 48),
        KpiTarget(targetId: 2, metric: "rhr_bpm", operator: "<=", threshold: 58),
        KpiTarget(targetId: 3, metric: "acwr", operator: "between", threshold: 0.8, thresholdHi: 1.3),
    ]

    static let history: [TrendPoint] = (0..<30).map { i in
        TrendPoint(date: Date(timeIntervalSince1970: 1_789_992_000 - Double(29 - i) * 86_400),
                   value: [48, 50, 47, 53, 51, 49, 52][i % 7] + Double(i % 3))
    }
}

struct KpiListNativePreview: View {
    private let theme = JITheme.native

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            JISectionHeader("My KPIs")
            Surface(padding: 16) {
                VStack(spacing: 0) {
                    ForEach(Array(L5KpiFixtures.rows.enumerated()), id: \.offset) { idx, row in
                        KpiSelectionRow(label: row.label, valueText: row.value, targetText: row.target,
                                        selected: idx < 4, canMoveUp: idx > 0, canMoveDown: idx < 3,
                                        showsReorder: idx < 4, identifierSuffix: "preview-\(idx)",
                                        onMoveUp: {}, onMoveDown: {}, onToggle: { _ in })
                        if idx != L5KpiFixtures.rows.count - 1 {
                            Divider().overlay(theme.color(.hairlineNested))
                        }
                    }
                }
            }
            JISectionHeader("Gate targets")
            KpiTargetsMirrorSection(targets: L5KpiFixtures.targets)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 8)
        .readableColumn()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.color(.bg))
    }
}

struct KpiDetailNativePreview: View {
    @State private var range: TrendRange = .month
    @State private var thresholdText = "48"
    private let theme = JITheme.native

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Surface {
                Text("52 ms").jiNumeral(.numeralLarge).foregroundStyle(theme.color(.text))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            JISectionHeader("Trend")
            Surface {
                TrendChart(points: Array(L5KpiFixtures.history.suffix(range.days)),
                           tint: theme.color(.info), unit: "ms", range: $range, showAll: nil)
            }
            JISectionHeader(kpiDetailPreviewAlertHeader)
            Surface {
                VStack(alignment: .leading, spacing: 10) {
                    Text(kpiDetailPreviewThresholdSentence).jiFont(.footnote).foregroundStyle(theme.color(.mutedNested))
                    HStack(spacing: 10) {
                        TextField("Threshold", text: $thresholdText).textFieldStyle(.roundedBorder)
                        Button("Save") {}.buttonStyle(.bordered).tint(theme.color(.info))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 8)
        .readableColumn()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.color(.bg))
    }
}


/// B-46 item 4 (fixer): the Gallery's KPI-detail mock renders the SAME copy as the shipped screen
/// — the sweep PNG showed the raw `hrv_weekly_avg >= …` key long after `KpiDetailView` was fixed.
/// Exposed as constants so a host test can assert them without rendering SwiftUI.
nonisolated let kpiDetailPreviewAlertHeader = "Alert"
nonisolated let kpiDetailPreviewThresholdSentence = kpiThresholdSentence(metricLabel: "HRV", operator: ">=")
