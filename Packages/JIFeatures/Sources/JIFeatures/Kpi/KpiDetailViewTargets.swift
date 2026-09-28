import SwiftUI
import JICore
import JICompute
import JIDesign

// W-TGT L3 (mock 03, spec §4) — KPI detail's Targets card: Goal · Rule · Your normal, and ONE Edit
// that opens the same editor sheet as Settings › Targets. Replaces the inline threshold editor
// (a second, online-only edit path for `plan.kpi_target`, B-54 (2)). Reads the document from the
// environment; no document injected (previews) = the card reads "no goal" / recommended, and no
// Edit button.
struct KpiDetailTargetsCard: View {
    let metric: KpiMetricId
    let normal: PersonalNormalResult?
    let sevenDay: Double?
    let decimals: Int
    let unit: String
    @Environment(\.targets) private var injectedDoc
    @Environment(\.targetsModel) private var targetsModel
    @State private var editing: TargetSubject?
    private let theme = JITheme.native

    private var document: TargetsDocument { targetsModel?.document ?? injectedDoc ?? .empty }

    var body: some View {
        if let subject = targetsSubject(for: metric), let lines = kpiTargetsCardLines(metric: metric, document: document) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    JISectionHeader("Targets")
                    if targetsModel != nil {
                        JIGlassButton("pencil", label: "Edit") { editing = subject }
                            .accessibilityIdentifier("kpi-detail-targets-edit")
                    }
                }
                Surface(level: 1, padding: 0) {
                    VStack(spacing: 0) {
                        if let goal = lines.goal { line(title: "Goal", tag: nil, value: goal, id: "goal") }
                        if let rule = lines.rule {
                            if lines.goal != nil { JIRowDivider().padding(.leading, 0) }
                            line(title: "Rule", tag: lines.ruleRecommended ? "recommended" : "yours", value: rule, id: "rule")
                        }
                        JIRowDivider().padding(.leading, 0)
                        line(title: "Your normal", tag: "computed", value: normalText, id: "normal")
                    }
                    .padding(.horizontal, JISpacing.s4).padding(.vertical, 6)
                }
                Text(kpiTargetsCardCaption).jiFont(.caption, tint: .muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s3)
            }
            .accessibilityIdentifier("kpi-detail-targets")
            .sheet(item: $editing) { s in
                TargetEditorSheet(subject: s, document: document,
                                  normal: TargetNormalInfo(lastSevenText: sevenDay.map(valueText), normalText: normal.map(bandText))) { next in
                    await targetsModel?.save(next)
                }
            }
        }
    }

    private var normalText: String {
        normal.map { "\(bandText($0)) · 28 days" } ?? "— \(JIMissingReason.calibrating.rawValue)"
    }

    private func bandText(_ n: PersonalNormalResult) -> String {
        "\(targetsNumber(n.low, decimals))–\(targetsNumber(n.high, decimals))"
    }

    private func valueText(_ v: Double) -> String {
        targetsNumber(v, decimals) + (unit.isEmpty ? "" : " \(unit)")
    }

    private func line(title: String, tag: String?, value: String, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: JISpacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).jiFont(.body, tint: .text)
                if let tag { Text(tag).jiFont(.caption, tint: tag == "yours" ? .info : .muted) }
            }
            Spacer(minLength: JISpacing.s2)
            Text(value).jiFont(.body, weight: .semibold, tint: value.hasPrefix("—") || value == "no goal" ? .muted : .text)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, JISpacing.s3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("kpi-detail-targets-\(id)")
    }
}

public nonisolated let kpiTargetsCardCaption = "One place to change these: Edit opens the same sheet as Settings › Targets."
