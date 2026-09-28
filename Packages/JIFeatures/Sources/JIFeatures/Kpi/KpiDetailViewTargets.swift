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
    @Environment(\.dynamicTypeSize) private var typeSize
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
                                  normal: kpiDetailTargetNormal) { next in
                    await targetsModel?.save(next)
                }
            }
        }
    }

    /// The same lines `targetNormalInfo` gives Settings › Targets (one computation, two doors).
    private var kpiDetailTargetNormal: TargetNormalInfo? {
        guard sevenDay != nil || normal != nil else { return nil }
        return TargetNormalInfo(lastSevenText: sevenDay.map(valueText), normalText: normal.map(bandText))
    }

    private var normalText: String {
        normal.map { "\(kpiTargetsNormalPrefix(metric))\(bandText($0)) · 28 days" } ?? "— \(JIMissingReason.calibrating.rawValue)"
    }

    private func bandText(_ n: PersonalNormalResult) -> String {
        "\(targetsNumber(n.low, decimals))–\(targetsNumber(n.high, decimals))"
    }

    private func valueText(_ v: Double) -> String {
        targetsNumber(v, decimals) + (unit.isEmpty ? "" : " \(unit)")
    }

    private func line(title: String, tag: String?, value: String, id: String) -> some View {
        // W-TGT fixer 2 R3: at accessibility sizes the row stacks (title · tag, then the value), so
        // "recommended" never hyphen-breaks in a squeezed left column.
        let ax = typeSize.isAccessibilitySize
        let layout = ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: JISpacing.s3))
        return layout {
            if ax {
                Text([title, tag].compactMap { $0 }.joined(separator: " · ")).jiFont(.body, tint: .text)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).jiFont(.body, tint: .text)
                    if let tag { Text(tag).jiFont(.caption, tint: tag == "yours" ? .info : .muted).lineLimit(1).fixedSize() }
                }
                .layoutPriority(1)
                Spacer(minLength: JISpacing.s2)
            }
            Text(value).jiFont(.body, weight: .semibold, tint: value.hasPrefix("—") || value == "no goal" ? .muted : .text)
                .multilineTextAlignment(ax ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, JISpacing.s3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("kpi-detail-targets-\(id)")
    }
}

/// The card's normal row names what it is a normal of when the goal is in another unit: the
/// Sleep KPI is the 0–100 score, its goal hours ("score 71–91 · 28 days").
public nonisolated func kpiTargetsNormalPrefix(_ metric: KpiMetricId) -> String {
    metric == .sleep ? "score " : ""
}

public nonisolated let kpiTargetsCardCaption = "One place to change these: Edit opens the same sheet as Settings › Targets."
