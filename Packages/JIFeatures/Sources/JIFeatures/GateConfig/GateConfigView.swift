import SwiftUI
import JICore
import JICompute
import JIDesign

// W5b-L3 (P-gate-config). Port of RN `app/gate-config.tsx`: header copy, three cards in RN's order
// (local morning-gate thresholds → fixture preview → local KPI rules → live server KPI targets),
// stepper rows (label · default · − value + · Reset), warn-coloured flipped verdict. Pushed from
// `GateConfigSection` (Settings › Preferences) — RN's only entry is its Settings row too.
public struct GateConfigView: View {
    @State private var model: GateConfigViewModel
    @Environment(\.jiTheme) private var theme
    /// B-33 §8.5: no hub fetch while the sweep renders this screen.
    @Environment(\.jiOffscreenRender) private var offscreen

    public init(model: GateConfigViewModel) { _model = State(initialValue: model) }

    public var body: some View {
        Form {
            Section {
                Text("Local overrides on the on-device compute ports' thresholds — not yet wired into any live verdict (see the preview below). Server KPI targets further down ARE live.")
                    .font(.footnote).foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("gateConfig.info")
            }
            morningSection
            previewSection
            kpiRulesSection
            serverSection
        }
        // §5: a `Form` keeps the system grouped background and the inset-grouped cells.
        .jiNativeFormChrome()   // `.insetGrouped` on iOS, no-op on the macOS test host
        .navigationTitle("Gate config")
        .task { if !offscreen { await model.load() } }
    }

    // MARK: - Section 1: local morning-gate overrides

    private var morningSection: some View {
        Section {
            if !model.loaded {
                Text("Loading…").font(.subheadline).foregroundStyle(theme.color(.muted))
            } else {
                ForEach(MorningGateOverridableField.allCases, id: \.rawValue) { field in
                    morningRow(field)
                }
                if !model.morningOverrides.isEmpty {
                    Button {
                        model.resetAllMorning()
                    } label: {
                        Text("Reset all to defaults").font(.subheadline.weight(.semibold)).foregroundStyle(theme.color(.info))
                    }
                    .buttonStyle(.pressableScale)
                    .accessibilityLabel("Reset all morning gate thresholds to defaults")
                    .accessibilityIdentifier("gateConfig.morning.resetAll")
                }
            }
        } header: {
            Text("Morning gate thresholds (local preview)")
        }
    }

    private func morningRow(_ field: MorningGateOverridableField) -> some View {
        let overridden = model.isOverridden(field)
        let unit = field.unit.map { " \($0)" } ?? ""
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(field.label).font(.subheadline).foregroundStyle(theme.color(.text))
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
                Text(baseline.verdict).font(.subheadline.weight(.bold)).foregroundStyle(theme.color(.text))
                    .accessibilityIdentifier("gateConfig.preview.baseline")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("With your overrides").font(.caption).foregroundStyle(theme.color(.muted))
                Text(withOverrides.verdict)
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
