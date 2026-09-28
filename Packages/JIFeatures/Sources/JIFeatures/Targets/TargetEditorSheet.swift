import SwiftUI
import JICore
import JIDesign

// W-TGT L3 (mock 02) — ONE editor sheet per metric, always the same blocks in the same order:
// Goal (field + basis where it applies, "Leave blank for none") · Rule (field, "recommended n",
// Reset) · Your normal (read-only, computed) · "Read by …". Settings › Targets, KPI detail's
// Targets card and the Goals overview all open this sheet. Numbers are typed or stepped; no bounds;
// blank is a first-class state ("no goal"; a blank rule = recommended).
public struct TargetEditorSheet: View {
    let subject: TargetSubject
    let normal: TargetNormalInfo?
    let onSave: (TargetsDocument) async -> Void
    private let document: TargetsDocument
    @State private var draft: TargetEditDraft
    @State private var error: String?
    @State private var saving = false
    @State private var hasDate: Bool
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss
    private let theme = JITheme.native

    public init(subject: TargetSubject, document: TargetsDocument, normal: TargetNormalInfo? = nil,
                onSave: @escaping (TargetsDocument) async -> Void) {
        self.subject = subject
        self.document = document
        self.normal = normal
        self.onSave = onSave
        let d = TargetEditDraft(subject: subject, document: document)
        _draft = State(initialValue: d)
        _hasDate = State(initialValue: d.weightDate != nil)
        _date = State(initialValue: d.weightDate.flatMap(targetEditorDay) ?? Date())
    }

    public var body: some View {
        NavigationStack {
            Form {
                if case .goal(let m) = subject { goalSection(m) }
                ForEach(subject.rules, id: \.self) { ruleSection($0) }
                normalSection
                if let error {
                    Section {
                        Text(error).jiFont(.footnote, tint: .danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("targetEditor.error")
                    }
                }
                Section {
                    Text("Read by: \(subject.readBy).").jiFont(.caption, tint: .muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("targetEditor.readBy")
                }
            }
            .jiNativeFormChrome()
            .scrollContentBackground(.hidden)
            .jiPageGround()
            .navigationTitle(subject.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("targetEditor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving)
                        .accessibilityIdentifier("targetEditor.save")
                }
            }
        }
        .jiTheme(.native)
    }

    private func save() async {
        var d = draft
        if case .goal(.weight) = subject { d.weightDate = hasDate ? targetEditorISO(date) : nil }
        switch d.applied(to: document) {
        case .failure(.unreadable(let field)):
            error = "\(field): type a number, or leave it blank."
        case .success(let next):
            saving = true
            await onSave(next)
            saving = false
            dismiss()
        }
    }

    // MARK: Goal

    @ViewBuilder private func goalSection(_ m: GoalMetric) -> some View {
        Section {
            field(title: m == .kcal ? "Daily goal" : targetsGoalTitle(m), text: $draft.goalText, unit: targetsGoalUnit(m),
                  step: targetsGoalStep(m), decimals: targetsGoalDecimals(m), fallback: nil, id: "goal")
            if m == .kcal {
                field(title: draft.deficitIsWeeklyLoss ? "Wanted loss" : "Wanted deficit", text: $draft.deficitText,
                      unit: draft.deficitIsWeeklyLoss ? "kg/week" : "kcal/day",
                      step: draft.deficitIsWeeklyLoss ? 0.1 : 50, decimals: draft.deficitIsWeeklyLoss ? 2 : 0, fallback: nil, id: "deficit")
                    .disabled(draft.trackerIncludesDeficit)
                Toggle("My tracker's goal already includes it", isOn: $draft.trackerIncludesDeficit)
                    .tint(theme.color(.info))
                    .accessibilityIdentifier("targetEditor.includesDeficit")
            }
            if m == .weight {
                Toggle("By a date", isOn: $hasDate).tint(theme.color(.info))
                    .accessibilityIdentifier("targetEditor.hasDate")
                if hasDate {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .accessibilityIdentifier("targetEditor.date")
                }
            }
        } header: {
            Text("Goal")
        } footer: {
            Text(goalFooter(m)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("targetEditor.goalFooter")
        }
    }

    private func goalFooter(_ m: GoalMetric) -> String {
        guard m == .kcal else { return "Leave blank for no goal. JI never fills one in." }
        guard let target = draft.kcalTargetPreview else { return "Leave the goal blank for none. JI never subtracts twice." }
        return "Target \(targetsNumber(target, 0)) kcal. Leave the goal blank for none. JI never subtracts twice."
    }

    // MARK: Rule

    @ViewBuilder private func ruleSection(_ r: RuleMetric) -> some View {
        let text = Binding(get: { draft.ruleTexts[r] ?? "" }, set: { draft.ruleTexts[r] = $0 })
        let typed: Double? = if case .value(let v) = targetsParse(text.wrappedValue) { v } else { nil }
        let recommended = typed.map { $0 == r.recommended } ?? true
        Section {
            if r == .hrvLowNights {
                Picker("How cautious", selection: Binding(get: { Int((typed ?? r.recommended).rounded()) },
                                                          set: { text.wrappedValue = String($0) })) {
                    ForEach(GatePreset.allCases, id: \.self) { Text($0.title).tag($0.hrvLowNights) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("targetEditor.preset")
                Text(GatePreset(hrvLowNights: typed).configSubtitle).jiFont(.caption, tint: .muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                field(title: targetsRuleTitle(r), text: text, unit: r.unit, step: targetsRuleStep(r),
                      decimals: targetsRuleDecimals(r), fallback: r.recommended, id: "rule.\(r.rawValue)")
            }
        } header: {
            Text("Rule · \(recommended ? "recommended" : "yours")")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(targetsRuleExplanation(r).prefix(1).uppercased() + targetsRuleExplanation(r).dropFirst()). Recommended \(targetsRuleValueText(r, r.recommended)).")
                    .fixedSize(horizontal: false, vertical: true)
                if !recommended {
                    Button("Reset to recommended") { text.wrappedValue = "" }
                        .buttonStyle(.borderless)
                        .tint(theme.color(.info))
                        .accessibilityIdentifier("targetEditor.reset.\(r.rawValue)")
                }
            }
        }
    }

    // MARK: Normal

    @ViewBuilder private var normalSection: some View {
        if case .goal = subject {
            Section {
                if let normal, normal.lastSevenText != nil || normal.normalText != nil {
                    if let last = normal.lastSevenText { LabeledContent("Last 7 days", value: last) }
                    if let band = normal.normalText { LabeledContent("Your normal", value: band) }
                } else {
                    Text("Shown on this metric's detail once there are enough days.").jiFont(.footnote, tint: .muted)
                }
            } header: {
                Text("Your normal · computed")
            } footer: {
                Text("Computed from your last 28 days. Never a goal, never stored.")
            }
            .accessibilityIdentifier("targetEditor.normal")
        }
    }

    // MARK: Field

    private func field(title: String, text: Binding<String>, unit: String?, step: Double, decimals: Int,
                       fallback: Double?, id: String) -> some View {
        TargetStepperField(title: title, text: text, unit: unit, step: step, decimals: decimals, fallback: fallback, id: id)
    }
}

/// A typed number with − / + (steps from the typed value, else the recommendation). The field
/// grows under its title at accessibility sizes so nothing truncates (AX3).
struct TargetStepperField: View {
    let title: String
    @Binding var text: String
    let unit: String?
    let step: Double
    let decimals: Int
    let fallback: Double?
    let id: String
    @Environment(\.dynamicTypeSize) private var typeSize
    private let theme = JITheme.native

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            Text(title).jiFont(.body, tint: .text).fixedSize(horizontal: false, vertical: true)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
            HStack(spacing: 8) {
                stepButton("minus") { text = TargetEditDraft.stepped(text, by: -step, decimals: decimals, from: fallback) }
                    .accessibilityLabel("\(title) decrease")
                    .accessibilityIdentifier("targetEditor.\(id).decrease")
                TextField("—", text: $text)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 48, maxWidth: typeSize.isAccessibilitySize ? .infinity : 80)
                    .numberPadKeyboard()
                    .accessibilityLabel(unit.map { "\(title) in \($0)" } ?? title)
                    .accessibilityIdentifier("targetEditor.\(id).field")
                if let unit { Text(unit).jiFont(.subheadline, tint: .muted).lineLimit(1).fixedSize() }
                stepButton("plus") { text = TargetEditDraft.stepped(text, by: step, decimals: decimals, from: fallback) }
                    .accessibilityLabel("\(title) increase")
                    .accessibilityIdentifier("targetEditor.\(id).increase")
            }
        }
    }

    private func stepButton(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph)
                .jiFont(.footnote, weight: .bold)
                .foregroundStyle(theme.color(.text))
                .frame(width: 30, height: 30)
                .background(theme.color(.surface2), in: Circle())
        }
        .buttonStyle(.pressableScale)
    }
}

nonisolated func targetEditorDay(_ iso: String) -> Date? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
    return f.date(from: String(iso.prefix(10)))
}

nonisolated func targetEditorISO(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
}
