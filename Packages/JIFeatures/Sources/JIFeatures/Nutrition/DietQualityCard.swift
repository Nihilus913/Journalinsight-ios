import SwiftUI
import JICore
import JIDesign

/// B-99 p5 — the Diet quality card under Macros on Nutrition (mockup BP-20 A/C): a 0–100 score
/// ring with "72 / 100" and its band line, the four contributor rows (Fibre / Sugar / Saturated
/// fat / Protein — the old Fibre and Sugar squares as rows), "How it is calculated ›" (opens
/// `DietQualitySheet`) and the always-on coverage caption. An incomplete day shows the gate's
/// line and no score; a day with no food shows neither (rule 5: never a 0 for missing data).
public struct DietQualityCard: View {
    let model: DietQualityPresentation
    let onShowMethod: () -> Void
    private let theme = JITheme.native

    public init(model: DietQualityPresentation, onShowMethod: @escaping () -> Void) {
        self.model = model; self.onShowMethod = onShowMethod
    }

    public var body: some View {
        Surface(level: 1, padding: JISpacing.cardPadding) {
            VStack(alignment: .leading, spacing: 12) {
                header
                if !model.rows.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.rows) { DietQualityRowView(row: $0) }
                    }
                }
                if model.state != .noData {
                    Button(action: onShowMethod) {
                        HStack {
                            Text("How it is calculated").jiFont(.subheadline, weight: .semibold)
                            Spacer()
                            Image(systemName: "chevron.right").jiFont(.footnote, weight: .semibold)
                        }
                        .foregroundStyle(theme.color(.info))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("diet-quality-how")
                }
                Text(model.caption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("diet-quality-caption")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diet-quality-card")
    }

    @ViewBuilder private var header: some View {
        switch model.state {
        case .scored(let score):
            HStack(alignment: .center, spacing: 14) {
                ScoreRing(value: Double(score), max: 100, tint: theme.color(.go), size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: "\(score)").jiNumeral(.numeralMedium).foregroundStyle(theme.color(.text))
                        Text("/ 100").jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                    }
                    Text(model.headline).jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(dietQualityTitle)
            .accessibilityValue("\(score) of 100, \(model.headline)")
            .accessibilityIdentifier("diet-quality-score")
        case .incomplete(let line):
            VStack(alignment: .leading, spacing: 4) {
                Text(line).jiFont(.cardTitle).foregroundStyle(theme.color(.text))
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.headline).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("diet-quality-incomplete")
        case .noData:
            VStack(alignment: .leading, spacing: 4) {
                Text("No food logged yet").jiFont(.cardTitle).foregroundStyle(theme.color(.text))
                Text(model.headline).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("diet-quality-nodata")
        }
    }
}

/// One contributor row: title + detail on the left, its 0–100 (or "n/a" / "—") on the right.
struct DietQualityRowView: View {
    let row: DietQualityRow
    private let theme = JITheme.native

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(.text))
                Text(row.detail).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(verbatim: row.scoreText).jiFont(.cardTitle).monospacedDigit()
                .foregroundStyle(theme.color(row.score == nil ? .muted : .text))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue("\(row.detail), \(row.score.map { "\($0) of 100" } ?? (row.scoreText == "n/a" ? "not available" : "not scored"))")
        .accessibilityIdentifier("diet-quality-row-\(row.key)")
    }
}

/// B-99 p5 — "How it is calculated" (mockup BP-20 B): the method in four steps, then the day's
/// contributors as rows. Read-only; one action: Done.
public struct DietQualitySheet: View {
    let model: DietQualityPresentation
    @Environment(\.dismiss) private var dismiss
    private let theme = JITheme.native

    public init(model: DietQualityPresentation) { self.model = model }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(dietQualitySheetIntro).jiFont(.body).foregroundStyle(theme.color(.text))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(dietQualityMethodSteps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(verbatim: "\(i + 1)").jiFont(.cardTitle).foregroundStyle(theme.color(.info))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title).jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(.text))
                                Text(step.body).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if !model.rows.isEmpty {
                        JISectionHeader("This day's contributors")
                        Surface(level: 1, padding: JISpacing.cardPadding) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(model.rows) { DietQualityRowView(row: $0) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Text(model.caption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(dietQualitySheetFootnote).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, JISpacing.sideMargin).padding(.vertical, 12)
            }
            .navigationTitle(dietQualityTitle)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("diet-quality-done")
                }
            }
        }
        .jiTheme(.native)
        .presentationDetents([.medium, .large])
        .jiSheetGround()
        .accessibilityIdentifier("diet-quality-sheet")
    }
}
