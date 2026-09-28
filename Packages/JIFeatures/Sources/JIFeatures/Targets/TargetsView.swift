import SwiftUI
import JICore
import JIDesign

// W-TGT L3 (mock 01) — Settings › Targets: ONE screen, three sections (Goals · Limits · Rules)
// over the ONE document. Replaces Settings › Goals / Goals setup and Gate thresholds (spec §4).
// A row opens the editor sheet (Goals, Rules, the HR cap as a Limit) or the zones screen. The
// "How the morning call works" card heads the Rules. W-GUI primitives: grouped cards on the
// ground, icon wells, one header, glass back.
public struct TargetsView: View {
    @Bindable var model: TargetsModel
    @State private var editing: TargetSubject?
    @State private var showZones = false
    @State private var showHowItWorks = false
    @State private var confirmReset = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.jiOffscreenRender) private var offscreen
    private let theme = JITheme.native
    private let today: () -> String

    public init(model: TargetsModel, today: @escaping () -> String = { ReminderScheduler.todayISO() }) {
        self.model = model
        self.today = today
    }

    public var body: some View {
        let doc = model.document
        ScreenScroll {
            VStack(alignment: .leading, spacing: 0) {
                if jiTitleWrapsInList(typeSize) {
                    Text("Targets").jiFont(.title, weight: .bold, tint: .text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, JISpacing.s4).padding(.bottom, JISpacing.s2)
                }
                Text(TargetsRows.subtitle).jiFont(.subheadline, tint: .muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, JISpacing.s4)
                    .accessibilityIdentifier("targets.subtitle")

                JISectionHeader(TargetsRows.goalsHeader)
                card(TargetsRows.goals(doc))
                footnote(TargetsRows.strengthFooter)

                JISectionHeader(TargetsRows.limitsHeader)
                card(TargetsRows.limits(doc, today: today()))
                if let cap = doc.limits.hrCapBpm, let limits = model.limitsModel {
                    // B-57 W4: the 8-week re-check answer (moved here from Gate thresholds).
                    Button("\(cap) is still right") { Task { await limits.confirmHrCap(); model.reload() } }
                        .buttonStyle(.jiSecondary)
                        .padding(.top, JISpacing.s3)
                        .accessibilityIdentifier("targets.confirmCap")
                }
                footnote(TargetsRows.limitsFooter)

                JISectionHeader(TargetsRows.rulesHeader)
                howItWorksCard
                card(TargetsRows.rules(doc))
                Button(TargetsRows.resetRules) { confirmReset = true }
                    .buttonStyle(.jiSecondary)
                    .padding(.top, JISpacing.s4)
                    .disabled(RuleMetric.allCases.allSatisfy(doc.isRecommended))
                    .accessibilityIdentifier("targets.resetRules")
                footnote(TargetsRows.resetFooter)
                if model.hubPending {
                    footnote("\(TargetsMirror.pendingText) — it syncs when the hub is reachable.")
                        .accessibilityIdentifier("targets.hubPending")
                }
                if let error = model.saveError {
                    Text(error).jiFont(.footnote, tint: .danger).padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s2)
                }
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
        .jiGlassBackButton()
        .jiTheme(.native)
        .navigationTitle("Targets")
        #if os(iOS)
        .navigationBarTitleDisplayMode(jiTitleWrapsInList(typeSize) ? .inline : .automatic)
        #endif
        .toolbar {
            // AX: the wrapped title above is the heading; an inline copy would only be cut again.
            if jiTitleWrapsInList(typeSize) {
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            }
        }
        .task { if !offscreen { model.reload() } }
        .sheet(item: $editing) { subject in
            TargetEditorSheet(subject: subject, document: model.document, normal: model.normal(for: subject),
                              onSaveCap: subject == .hrCap ? model.limitsModel.map { limits in
                                  { text in
                                      let ok = await limits.changeHrCap(text)
                                      model.reload()
                                      return ok
                                  }
                              } : nil) { next in await model.save(next) }
        }
        .navigationDestination(isPresented: $showZones) {
            if let limits = model.limitsModel { TargetsZonesScreen(limits: limits) { model.reload() } }
        }
        .navigationDestination(isPresented: $showHowItWorks) {
            if let limits = model.limitsModel {
                GateConfigView(model: limits).onDisappear { model.reload() }
            } else {
                GateConfigExplainer()
            }
        }
        .confirmationDialog(TargetsRows.resetRules, isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset rules") { Task { await model.resetRules() } }
                .accessibilityIdentifier("targets.resetRules.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(TargetsRows.resetFooter)
        }
    }

    // MARK: Pieces

    private var howItWorksCard: some View {
        Surface(level: 1, padding: 0) {
            VStack(alignment: .leading, spacing: JISpacing.s2) {
                Button { showHowItWorks = true } label: {
                    JIChevronRow(title: "How the morning call works", systemImage: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("targets.howItWorks")
                Text(TargetsRows.rulesIntro).jiFont(.footnote, tint: .muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, JISpacing.s4).padding(.vertical, JISpacing.s3)
        }
        .padding(.bottom, JISpacing.s3)
    }

    private func footnote(_ text: String) -> some View {
        Text(text).jiFont(.caption, tint: .muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s2)
    }

    private func card(_ rows: [TargetsRow]) -> some View {
        Surface(level: 1, padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { JIRowDivider().padding(.leading, JIChevronRowMetrics.iconWell + JISpacing.s3) }
                    rowView(row)
                }
            }
            .padding(.horizontal, JISpacing.s4).padding(.vertical, 4)
        }
    }

    @ViewBuilder private func rowView(_ row: TargetsRow) -> some View {
        if row.subject == .avoidZone5 {
            if let limits = model.limitsModel {
                Toggle(isOn: Binding(get: { model.document.limits.avoidZone5 },
                                     set: { on in Task { await limits.setAvoidZone5(on); model.reload() } })) {
                    TargetsRowLabel(row: row, showsValue: false)
                }
                .tint(theme.color(.info))
                .disabled(model.document.limits.zones == nil)
                .padding(.vertical, JISpacing.s2)
                .accessibilityIdentifier("targets.row.\(row.id)")
            } else {
                TargetsRowLabel(row: row, showsValue: true).padding(.vertical, JISpacing.s2)
                    .accessibilityIdentifier("targets.row.\(row.id)")
            }
        } else {
            Button { open(row.subject) } label: {
                HStack(spacing: JISpacing.s2) {
                    TargetsRowLabel(row: row, showsValue: true)
                    if isEditable(row.subject) {
                        Image(systemName: JIChevronRowMetrics.chevron)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.color(.mutedNested))
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, JISpacing.s2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEditable(row.subject))
            .accessibilityHint(isEditable(row.subject) ? "Opens the editor" : "")
            .accessibilityIdentifier("targets.row.\(row.id)")
        }
    }

    private func isEditable(_ s: TargetSubject) -> Bool {
        switch s {
        case .hrCap, .zones, .avoidZone5: model.canEditLimits
        case .goal, .rule, .loadBand: true
        }
    }

    private func open(_ s: TargetSubject) {
        switch s {
        case .hrCap: editing = s   // spec §4: the ONE editor, with Limit instead of Goal
        case .zones: showZones = true
        case .avoidZone5: break
        case .goal, .rule, .loadBand: editing = s
        }
    }
}

/// Icon well · title + subtitle (+ "recommended"/"yours") · value. At accessibility sizes the
/// value drops under the title (nothing truncates at AX3).
struct TargetsRowLabel: View {
    let row: TargetsRow
    let showsValue: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    private let theme = JITheme.native

    var body: some View {
        HStack(alignment: .center, spacing: JISpacing.s3) {
            Image(systemName: row.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.color(row.tint))
                .frame(width: JIChevronRowMetrics.iconWell, height: JIChevronRowMetrics.iconWell)
                .background(theme.color(row.tint).opacity(0.16), in: RoundedRectangle(cornerRadius: JIChevronRowMetrics.iconWellRadius, style: .continuous))
                .accessibilityHidden(true)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    texts
                    if showsValue { valueText }
                }
                Spacer(minLength: 0)
            } else {
                texts
                Spacer(minLength: JISpacing.s2)
                if showsValue { valueText }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title).jiFont(.body, tint: .text).fixedSize(horizontal: false, vertical: true)
            if let subtitle = row.subtitle {
                Text(subtitle).jiFont(.caption, tint: .muted).fixedSize(horizontal: false, vertical: true)
            }
            if let tag = row.ruleTag {
                Text(tag).jiFont(.caption, weight: .semibold, tint: tag == "yours" ? .info : .muted)
                    .accessibilityIdentifier("targets.row.\(row.id).tag")
            }
        }
    }

    private var valueText: some View {
        Text(row.value).jiFont(.body, weight: .semibold, tint: row.value.hasPrefix("—") || row.value == "No cap" ? .muted : .text)
            .monospacedDigit()
            .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("targets.row.\(row.id).value")
    }
}

/// Targets › Zones: the user's own zones (max HR or LTHR → five floors; each floor editable).
struct TargetsZonesScreen: View {
    @Bindable var limits: GateConfigViewModel
    let onChange: () -> Void

    var body: some View {
        Form { HrZonesSection(model: limits) }
            .jiNativeFormChrome()
            .scrollContentBackground(.hidden)
            .jiPageGround()
            .jiGlassBackButton()
            .navigationTitle("Zones")
            .onChange(of: limits.gateSettings) { _, _ in onChange() }
            .jiTheme(.native)
    }
}
