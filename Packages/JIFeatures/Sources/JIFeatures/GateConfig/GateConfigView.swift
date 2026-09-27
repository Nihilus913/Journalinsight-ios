import SwiftUI
import JICore
import JICompute
import JIDesign

// W5b-L3 (P-gate-config). Port of RN `app/gate-config.tsx`: header copy, three cards in RN's order
// (local morning-gate thresholds → fixture preview → local KPI rules → live server KPI targets),
// stepper rows (label · default · − value + · Reset), warn-coloured flipped verdict. Pushed from
// `GateConfigSection` (Settings › Preferences) — RN's only entry is its Settings row too.
/// B-57 W1: the "How the morning call works" card rows.
public nonisolated let gateConfigMorningCallRows: [(word: String, role: JIColorRole, text: String)] = [
    (VerdictUserWord.full, .go, "Signals sit where they should. Train as planned."),
    (VerdictUserWord.modified, .reduced, "A signal stays low. Same day, easier: intervals become easy Z2."),
    (VerdictUserWord.rest, .danger, "Several signals are off at once. Walk and recover."),
]

public struct GateConfigView: View {
    @State private var model: GateConfigViewModel
    @Environment(\.jiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// B-33 §8.5: no hub fetch while the sweep renders this screen.
    @Environment(\.jiOffscreenRender) private var offscreen

    public init(model: GateConfigViewModel) { _model = State(initialValue: model) }
    @Environment(\.recoveryInsight) private var recoveryInsight
    @State private var showCapSheet = false
    @State private var showWalkthrough = false
    /// Held for the cover's lifetime so a re-render never restarts the walk-through.
    @State private var walkthroughModel: OnboardingViewModel?

    public var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("How the morning call works").jiFont(.cardTitle).foregroundStyle(theme.color(.text))
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
                // DEV-07: a chevron row, not a tinted text link (W-B57-W4 fixer).
                Button {
                    walkthroughModel = model.makeOnboardingModel()
                    showWalkthrough = true
                } label: {
                    JIChevronRow(title: "Walk me through it again", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("gateConfig.walkthrough")
            } footer: {
                Text("Recommended values are already set. Change one only when you know why.")
            }
            Section {
                Button { showCapSheet = true } label: {
                    JIChevronRow { valueRow(gateConfigHrCapTitle, model.capSubtitle, value: model.capValueText) }
                }
                .buttonStyle(.plain)
                .accessibilityHint(model.gateSettings.hasCap ? "Change your cap" : "Add a limit")
                .accessibilityIdentifier("gateConfig.hrCap")
                if let recheck = model.recheckSubtitle, let cap = model.gateSettings.hrCapBpm {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Re-check reminder").font(.subheadline).foregroundStyle(theme.color(.text))
                            Text(recheck).font(.caption2).foregroundStyle(theme.color(.muted))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Text("\(GateSettings.recheckWeeks) wk").font(.subheadline).foregroundStyle(theme.color(.muted))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("gateConfig.recheck")
                    // DEV-07: a secondary button, not a tinted text link (W-B57-W4 fixer).
                    Button("\(cap) is still right") { Task { await model.confirmHrCap() } }
                    .buttonStyle(.jiSecondary)
                    .accessibilityIdentifier("gateConfig.confirmCap")
                }
            } header: {
                Text("Safety")
            } footer: {
                if model.hubPending {
                    Text("\(GateSettingsMirror.pendingText) — it syncs when the hub is reachable.")
                        .accessibilityIdentifier("gateConfig.hubPending")
                }
            }
            HrZonesSection(model: model)
            ForEach([GateConfigGroup.recoverySignals, .sleep, .fuel], id: \.self) { group in
                Section(group.rawValue) {
                    if !model.loaded {
                        Text("Loading…").font(.subheadline).foregroundStyle(theme.color(.muted))
                    } else {
                        if group == .recoverySignals { presetRow }
                        if group == .sleep { sleepGoalRow }
                        ForEach(MorningGateOverridableField.allCases.filter { $0.group == group }, id: \.rawValue) { morningRow($0) }
                    }
                }
            }
            previewSection
            Section {
                Button { model.useRecommended() } label: { Text("Use recommended").frame(maxWidth: .infinity) }
                    .buttonStyle(.jiPrimary)   // W-GUI T6: accent, never a metric colour (BUG-31)
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                    .accessibilityIdentifier("gateConfig.useRecommended")
            } footer: {
                Text("Calorie, protein and weight targets live in Goals.")
            }
            DisclosureGroup("Advanced") { kpiRulesSection; serverSection }
                .accessibilityIdentifier("gateConfig.advanced")
        }
        // §5: a `Form` keeps the system grouped background and the inset-grouped cells.
        .jiNativeFormChrome()
        .scrollContentBackground(.hidden)   // W-GUI tier B: on the page ground
        .jiPageGround()
        .jiGlassBackButton()   // `.insetGrouped` on iOS, no-op on the macOS test host
        .navigationTitle("Gate thresholds")
        .task { if !offscreen { await model.load() } }
        .sheet(isPresented: $showCapSheet) {
            HrCapChangeSheet(current: model.gateSettings.hrCapBpm) { await model.changeHrCap($0) }
        }
        .onboardingCover(isPresented: $showWalkthrough) {
            if let walkthroughModel {
                OnboardingFlowView(model: walkthroughModel) { showWalkthrough = false; model.loadLocal() }
            }
        }
    }

    /// B-57 W4 "How cautious": the preset decides how many low-HRV nights turn the call red.
    private var presetRow: some View {
        Picker(selection: Binding(get: { model.gateSettings.preset },
                                  set: { p in Task { await model.setPreset(p) } })) {
            ForEach(GatePreset.allCases, id: \.self) { Text($0.title).tag($0) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("How cautious").font(.subheadline).foregroundStyle(theme.color(.text))
                Text(model.gateSettings.preset.configSubtitle).font(.caption2).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .pickerStyle(.menu)
        .tint(theme.color(.info))
        .accessibilityIdentifier("gateConfig.preset")
    }

    // MARK: - Morning-gate rows (grouped by `GateConfigGroup`)

    private func morningRow(_ field: MorningGateOverridableField) -> some View {
        let overridden = model.isOverridden(field)
        let unit = field.unit.map { " \($0)" } ?? ""
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(field.label).font(.subheadline).foregroundStyle(theme.color(.text))
                Text(field.explanation).font(.caption2).foregroundStyle(theme.color(.muted))
                Text("default \(gateConfigFormat(field.value(in: .default)))\(unit)\(overridden ? " · overridden" : "")")
                    .font(.caption2).foregroundStyle(theme.color(.muted))
            }
            Spacer(minLength: 4)
            stepButton(glyph: "minus") { model.bump(field, direction: -1) }
                .accessibilityLabel("\(field.label) decrease")
                .accessibilityIdentifier("gateConfig.morning.\(field.rawValue).decrease")
            Text("\(gateConfigFormat(model.value(for: field)))\(unit)")
                .font(.subheadline.weight(.bold)).foregroundStyle(theme.color(.text))
                .frame(minWidth: 68).multilineTextAlignment(.center)
                .accessibilityIdentifier("gateConfig.morning.\(field.rawValue).value")
            stepButton(glyph: "plus") { model.bump(field, direction: 1) }
                .accessibilityLabel("\(field.label) increase")
                .accessibilityIdentifier("gateConfig.morning.\(field.rawValue).increase")
            if overridden {
                resetChip { model.reset(field) }
                    .accessibilityLabel("Reset \(field.label)")
                    .accessibilityIdentifier("gateConfig.morning.\(field.rawValue).reset")
            }
        }
        .accessibilityIdentifier("gateConfig.morning.row.\(field.rawValue)")
    }

    // MARK: - Fixture-evaluation preview

    private var previewSection: some View {
        let baseline = GateConfigViewModel.baselinePreview
        let withOverrides = model.previewWithOverrides
        let flipped = model.verdictFlipped
        return Section {
            Text("Runs the real evaluate() against one bundled interval-day row (2026-08-25, 6.2h sleep). This demonstrates the override reaching the compute port — it does not affect Today or Training.")
                .font(.caption).foregroundStyle(theme.color(.muted))
            VStack(alignment: .leading, spacing: 2) {
                Text("Default").font(.caption).foregroundStyle(theme.color(.muted))
                Text(baseline.displayVerdict).font(.subheadline.weight(.bold)).foregroundStyle(theme.color(.text))
                    .accessibilityIdentifier("gateConfig.preview.baseline")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("With your overrides").font(.caption).foregroundStyle(theme.color(.muted))
                Text(withOverrides.displayVerdict)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(flipped ? theme.color(.reduced) : theme.color(.text))
                    .accessibilityIdentifier("gateConfig.preview.withOverrides")
                if flipped {
                    Text("Flipped by your override(s).").font(.caption).foregroundStyle(theme.color(.reduced))
                        .accessibilityIdentifier("gateConfig.preview.flipped")
                }
            }
        } header: {
            Text("Fixture preview — not live")
        }
    }

    // MARK: - Section 2: local KPI-rule overrides

    private var kpiRulesSection: some View {
        Section {
            if !model.loaded {
                Text("Loading…").font(.subheadline).foregroundStyle(theme.color(.muted))
            } else {
                // `KpiRule` is not `Hashable`; `kpiRuleKey` is the row identity (unique per row).
                ForEach(defaultKpiRules.map { (key: kpiRuleKey($0), rule: $0) }, id: \.key) { entry in
                    kpiRuleRow(entry.rule)
                }
            }
        } header: {
            Text("KPI gate rules (local preview)")
        }
    }

    private func kpiRuleRow(_ rule: KpiRule) -> some View {
        let key = kpiRuleKey(rule)
        let overridden = model.isKpiOverridden(key)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(rule.metric) \(rule.operator)").font(.subheadline).foregroundStyle(theme.color(.text))
                Text("\(rule.description)\(overridden ? " · overridden" : "")")
                    .font(.caption2).foregroundStyle(theme.color(.muted)).lineLimit(1)
            }
            Spacer(minLength: 4)
            stepButton(glyph: "minus") { model.bumpKpi(rule, direction: -1) }
                .accessibilityLabel("\(key) threshold decrease")
                .accessibilityIdentifier("gateConfig.kpi.\(key).decrease")
            Text(gateConfigFormat(model.kpiThreshold(for: rule)))
                .font(.subheadline.weight(.bold)).foregroundStyle(theme.color(.text))
                .frame(minWidth: 56).multilineTextAlignment(.center)
                .accessibilityIdentifier("gateConfig.kpi.\(key).value")
            stepButton(glyph: "plus") { model.bumpKpi(rule, direction: 1) }
                .accessibilityLabel("\(key) threshold increase")
                .accessibilityIdentifier("gateConfig.kpi.\(key).increase")
            if overridden {
                resetChip { model.resetKpi(key) }
                    .accessibilityLabel("Reset \(key) threshold")
                    .accessibilityIdentifier("gateConfig.kpi.\(key).reset")
            }
        }
        .accessibilityIdentifier("gateConfig.kpi.row.\(key)")
    }

    // MARK: - Section 3: LIVE server KPI targets

    private var serverSection: some View {
        Section {
            Text("These drive the real Training-tab gate recommendation right now (plan.kpi_target).")
                .font(.caption).foregroundStyle(theme.color(.muted))
            if !model.hasServerProvider {
                // Rule 5: never a silent zero — say why the block is empty.
                Text("No hub connection saved — connect in Settings › Connection to edit live targets.")
                    .font(.caption).foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("gateConfig.server.noHub")
            } else {
                switch model.serverPhase {
                case .idle, .loading:
                    Text("Loading…").font(.subheadline).foregroundStyle(theme.color(.muted))
                case .error(let message):
                    Text("Couldn't load server targets.").font(.caption).foregroundStyle(theme.color(.danger))
                        .accessibilityIdentifier("gateConfig.server.loadError")
                    Text(message).font(.caption2).foregroundStyle(theme.color(.muted))
                    Button {
                        Task { await model.loadServer() }
                    } label: {
                        Text("Retry").font(.subheadline.weight(.semibold)).foregroundStyle(theme.color(.info))
                    }
                    .buttonStyle(.pressableScale)
                    .accessibilityLabel("Retry loading server targets")
                    .accessibilityIdentifier("gateConfig.server.retry")
                case .loaded:
                    ForEach(model.serverTargets) { target in
                        serverRow(target)
                    }
                }
                if let saveError = model.serverSaveError {
                    Text(saveError).font(.caption).foregroundStyle(theme.color(.danger))
                        .accessibilityIdentifier("gateConfig.server.saveError")
                }
            }
        } header: {
            Text("Server KPI targets — live")
        }
    }

    private func serverRow(_ target: KpiTarget) -> some View {
        let name = "\(target.metric) \(target.operator)"
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline).foregroundStyle(theme.color(.text))
                if let description = target.description, !description.isEmpty {
                    Text(description).font(.caption2).foregroundStyle(theme.color(.muted)).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            stepButton(glyph: "minus") { Task { await model.nudgeServer(target, direction: -1) } }
                .accessibilityLabel("Server \(name) decrease")
                .accessibilityIdentifier("gateConfig.server.\(target.targetId).decrease")
            Text(gateConfigFormat(target.threshold))
                .font(.subheadline.weight(.bold)).foregroundStyle(theme.color(.text))
                .frame(minWidth: 56).multilineTextAlignment(.center)
                .accessibilityIdentifier("gateConfig.server.\(target.targetId).value")
            stepButton(glyph: "plus") { Task { await model.nudgeServer(target, direction: 1) } }
                .accessibilityLabel("Server \(name) increase")
                .accessibilityIdentifier("gateConfig.server.\(target.targetId).increase")
        }
        .accessibilityIdentifier("gateConfig.server.row.\(target.targetId)")
    }

    // MARK: - Controls

    /// B-57 W3 S3: "Sleep goal" — read-only, the gate's own goal; never a stepper or a floor.
    private var sleepGoalRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(gateConfigSleepGoalTitle).font(.subheadline).foregroundStyle(theme.color(.text))
                Text(gateConfigSleepGoalExplanation(recovery: recoveryInsight?.result, config: .default)).font(.caption2).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Text(gateConfigSleepGoalValue(.default)).font(.subheadline.weight(.bold)).foregroundStyle(theme.color(.text))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("gateConfig.sleepGoal")
    }

    /// W-B57-W3 fixer: a user value shown read-only here (no lock, no danger tint — it is theirs).
    private func valueRow(_ title: String, _ subtitle: String, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(theme.color(.text))
                Text(subtitle).font(.caption2).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(theme.color(.text))
        }
        .accessibilityElement(children: .combine)
    }

    /// RN `StepButton` (`PressableScale variant="stepper"`, 30 pt circle on `surface2`); press-in
    /// scale is the button style's job (rule 7).
    private func stepButton(glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph)
                .jiFont(.footnote, weight: .bold)
                .foregroundStyle(theme.color(.text))
                .frame(width: 30, height: 30)
                .background(theme.color(.surface2), in: Circle())
        }
        .buttonStyle(.pressableScale)
    }

    /// RN `ResetChip` — small `accent2` text button, only shown while the row is overridden.
    private func resetChip(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Reset").font(.caption2.weight(.bold)).foregroundStyle(theme.color(.info))
        }
        .buttonStyle(.pressableScale)
    }
}
