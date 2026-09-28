import SwiftUI
import JICore
import JIDesign

// W5b-L3 (P-gate-config) → W-TGT L3 (spec §4): Gate thresholds merged into Settings › Targets.
// What stays is the verdict explainer + the walk-through row — the Rules header
// card's destination (Targets) and Decide's row. The morning-gate / KPI-rule overrides, the
// fixture preview and "Advanced" (the live `plan.kpi_target` block) are deleted: one edit path.
/// B-57 W1: the "How the morning call works" card rows.
public nonisolated let gateConfigMorningCallRows: [(word: String, role: JIColorRole, text: String)] = [
    (VerdictUserWord.full, .go, "Signals sit where they should. Train as planned."),
    (VerdictUserWord.modified, .reduced, "A signal stays low. Same day, easier: intervals become easy Z2."),
    (VerdictUserWord.rest, .danger, "Several signals are off at once. Walk and recover."),
]

public struct GateConfigView: View {
    @State private var model: GateConfigViewModel
    /// B-33 §8.5: no store read while the sweep renders this screen.
    @Environment(\.jiOffscreenRender) private var offscreen

    public init(model: GateConfigViewModel) { _model = State(initialValue: model) }
    @Environment(\.recoveryInsight) private var recoveryInsight
    /// Held for the cover's lifetime so a re-render never restarts the walk-through; non-nil = shown
    /// (W-FIX5 W4-2: the cover is item-driven, so it never renders before the model exists).
    @State private var walkthroughModel: OnboardingViewModel?

    public var body: some View {
        Form {
            GateConfigHowItWorksSection {
                // DEV-07: a chevron row, not a tinted text link (W-B57-W4 fixer).
                Button {
                    // W4-2: the real night count ("Nights so far"), never a guess.
                    walkthroughModel = model.makeOnboardingModel(recovery: recoveryInsight?.result)
                } label: {
                    JIChevronRow(title: "Walk me through it again", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("gateConfig.walkthrough")
            }
        }
        // §5: a `Form` keeps the system grouped background and the inset-grouped cells.
        .jiNativeFormChrome()
        .scrollContentBackground(.hidden)   // W-GUI tier B: on the page ground
        .jiPageGround()
        .jiGlassBackButton()   // `.insetGrouped` on iOS, no-op on the macOS test host
        .navigationTitle(gateConfigTitle)
        .task { if !offscreen { await model.load() } }
        .onboardingCover(item: $walkthroughModel) { walkthrough in
            OnboardingFlowView(model: walkthrough) { walkthroughModel = nil; model.loadLocal() }
                .environment(\.recoveryInsight, recoveryInsight)
        }
    }
}

/// W-TGT: the screen's title — the Rules header card's link says the same words.
public nonisolated let gateConfigTitle = "How the morning call works"
/// W-TGT: where the numbers went (spec §4: Gate thresholds merged into Targets).
public nonisolated let gateConfigFooter = "Your rules, HR cap and zones are in Settings › Targets. Recommended rules are already set; change one only when you know why."

/// The three verdict words and what each means (+ an optional trailing row, e.g. the walk-through).
struct GateConfigHowItWorksSection<Trailing: View>: View {
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.jiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(gateConfigTitle).jiFont(.cardTitle).foregroundStyle(theme.color(.text))
                ForEach(gateConfigMorningCallRows, id: \.word) { row in
                    // AX sizes: the word sits above its line, so "Modified" never splits mid-word.
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                    layout {
                        Text(row.word).jiFont(.body, weight: .bold).foregroundStyle(theme.color(row.role))
                            .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 90, alignment: .leading)
                        Text(row.text).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("gateConfig.howItWorks")
            trailing()
        } footer: {
            Text(gateConfigFooter).accessibilityIdentifier("gateConfig.footer")
        }
    }
}

/// The explainer without the walk-through (no Limits engine, e.g. a preview).
struct GateConfigExplainer: View {
    var body: some View {
        Form { GateConfigHowItWorksSection { EmptyView() } }
            .jiNativeFormChrome()
            .scrollContentBackground(.hidden)
            .jiPageGround()
            .jiGlassBackButton()
            .navigationTitle(gateConfigTitle)
    }
}
