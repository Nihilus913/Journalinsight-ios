import SwiftUI
import JICore
import JIDesign

private struct StepTitle: View {
    let title: String, subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.weight(.heavy)).foregroundStyle(JITheme.native.color(.text))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).jiFont(.body).foregroundStyle(JITheme.native.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Board 08 — "Your morning call".
struct OnboardingWelcomeStep: View {
    private let theme = JITheme.native
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepTitle(title: OnboardingCopy.welcomeTitle, subtitle: OnboardingCopy.welcomeSubtitle)
            ForEach(OnboardingCopy.welcomeRows, id: \.word) { row in
                Surface {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.word).jiFont(.cardTitleLarge, weight: .heavy).foregroundStyle(theme.color(row.role))
                        Text(row.text).jiFont(.body).foregroundStyle(theme.color(.muted))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }
            Text(OnboardingCopy.welcomeFooter).jiFont(.body).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Board 09 — "First, it learns your normal". The nights card never invents a count.
struct OnboardingBaselineStep: View {
    let nights: OnboardingViewModel.NightsProgress?
    /// W-FIX5 W4-2: the first-launch cover is built before the recovery score has loaded; the
    /// shell's live insight fills the card when it lands (still "— Calibrating" without one).
    @Environment(\.recoveryInsight) private var recoveryInsight
    private let theme = JITheme.native
    private var shown: OnboardingViewModel.NightsProgress? {
        nights ?? OnboardingViewModel.NightsProgress(recovery: recoveryInsight?.result)
    }
    var body: some View {
        let nights = shown
        return VStack(alignment: .leading, spacing: 16) {
            StepTitle(title: OnboardingCopy.baselineTitle, subtitle: OnboardingCopy.baselineSubtitle)
            Surface {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Overnight HRV · example", systemImage: "waveform.path.ecg")
                        .jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(.reduced))
                    NormalBar(value: 25, normal: 27...30, unit: "ms", tint: .reduced)
                    Text(OnboardingCopy.baselineExampleCaption).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nights so far").jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(.text))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(OnboardingCopy.nightsValue(nights)).jiNumeral(.numeralLarge).foregroundStyle(theme.color(.info))
                        if let n = nights { Text("of \(n.need)").jiFont(.body).foregroundStyle(theme.color(.muted)) }
                        if let reason = OnboardingCopy.nightsReason(nights) {
                            Text(reason).jiFont(.body).foregroundStyle(theme.color(.muted))
                        }
                    }
                    if let n = nights {
                        ProgressView(value: Double(min(n.have, n.need)), total: Double(max(n.need, 1))).tint(theme.color(.info))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("onboarding.nights")
            }
            HowWeCalculateLink("How JI learns your normal", title: "Your normal", steps: OnboardingCopy.baselineSteps)
            Text(OnboardingCopy.baselineFooter).jiFont(.body).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Board 10 — "Your limits": optional cap (Yes/No, nothing filled in), the user's zones (optional),
/// Avoid Zone 5 (optional, needs zones), and a medication the user types.
struct OnboardingSafetyStep: View {
    @Bindable var model: OnboardingViewModel
    @State private var editingMedication = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let theme = JITheme.native

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepTitle(title: OnboardingCopy.safetyTitle, subtitle: OnboardingCopy.safetySubtitle)
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    Text(OnboardingCopy.capQuestion).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                        .fixedSize(horizontal: false, vertical: true)
                    Picker(OnboardingCopy.capQuestion, selection: Binding(get: { model.wantsCap }, set: { model.wantsCap = $0 })) {
                        Text("Yes").tag(Bool?.some(true))
                        Text("No").tag(Bool?.some(false))
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("onboarding.wantsCap")
                    if model.wantsCap == true { capRow } else if model.wantsCap == false {
                        Text(OnboardingCopy.capNoNote).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let e = model.capError {
                        Text(e).jiFont(.footnote).foregroundStyle(theme.color(.danger))
                            .accessibilityIdentifier("onboarding.capError")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(OnboardingCopy.safetyDoctorNote).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
            JISectionHeader(OnboardingCopy.zonesTitle)
            Surface { zonesCard.frame(maxWidth: .infinity, alignment: .leading) }
            JISectionHeader("Medication")
            Surface { medicationCard.frame(maxWidth: .infinity, alignment: .leading) }
            Text(OnboardingCopy.safetyMedicationNote).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $editingMedication) {
            MedicationEditorSheet(entry: model.medication ?? MedicationEntry()) { model.saveMedication($0) }
        }
    }

    private var capRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text("Heart-rate cap").jiFont(.body).foregroundStyle(theme.color(.text))
                Text(OnboardingCopy.capYesNote).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
            HStack(spacing: 8) {
                TextField("bpm", text: $model.hrCapText)
                    .multilineTextAlignment(.trailing).frame(minWidth: 56, maxWidth: 96)
                    .jiNumeral(.numeralSmall).foregroundStyle(theme.color(.danger))
                    .numberPadKeyboard()
                    .accessibilityLabel("Heart-rate cap in bpm")
                    .accessibilityIdentifier("onboarding.hrCap")
                // W-FIX5 W4-4: the unit never wraps ("bp/m") at default size.
                Text("bpm").jiFont(.footnote).foregroundStyle(theme.color(.muted)).lineLimit(1).fixedSize()
                Button { model.bumpCap(-1) } label: { Image(systemName: "minus") }
                    .accessibilityLabel("Lower cap").accessibilityIdentifier("onboarding.capMinus")
                Button { model.bumpCap(+1) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Raise cap").accessibilityIdentifier("onboarding.capPlus")
            }
            .buttonStyle(.bordered)
            .tint(theme.color(.info))
        }
    }

    private var zonesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("From", selection: $model.zoneAnchor) {
                ForEach(HrZoneAnchor.allCases, id: \.self) { Text($0 == .maxHr ? "Max HR" : "LTHR").tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onboarding.zoneAnchorKind")
            HStack {
                Text(model.zoneAnchor.title).jiFont(.body).foregroundStyle(theme.color(.text))
                Spacer()
                TextField("bpm", text: $model.zoneAnchorText)
                    .multilineTextAlignment(.trailing).frame(minWidth: 56, maxWidth: 96)
                    .numberPadKeyboard()
                    .accessibilityLabel("\(model.zoneAnchor.title) in bpm")
                    .accessibilityIdentifier("onboarding.zoneAnchor")
                Text("bpm").jiFont(.footnote).foregroundStyle(theme.color(.muted)).lineLimit(1).fixedSize()
            }
            if let z = model.zonesPreview {
                ForEach(1...5, id: \.self) { i in
                    HStack {
                        Text("Zone \(i)").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        Spacer()
                        Text("\(z.rangeText(i)) bpm").jiFont(.footnote).foregroundStyle(theme.color(.text))
                    }
                    .accessibilityElement(children: .combine)
                }
                Toggle(isOn: $model.avoidZone5) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(OnboardingCopy.avoidZone5Title).jiFont(.body).foregroundStyle(theme.color(.text))
                        Text(OnboardingCopy.avoidZone5Note).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(theme.color(.info))
                .accessibilityIdentifier("onboarding.avoidZone5")
            }
            if let e = model.zoneError {
                Text(e).jiFont(.footnote).foregroundStyle(theme.color(.danger))
                    .accessibilityIdentifier("onboarding.zoneError")
            }
            Text(OnboardingCopy.zonesNote).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var medicationCard: some View {
        if let med = model.medication {
            Button { editingMedication = true } label: {
                JIChevronRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(med.name).jiFont(.body).foregroundStyle(theme.color(.text))
                        Text([med.dose, "Added by you"].filter { !$0.isEmpty }.joined(separator: " · "))
                            .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    }
                    Spacer()
                    Text("Edit").jiFont(.subheadline).foregroundStyle(theme.color(.info))
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.medication")
        } else {
            Button { editingMedication = true } label: {
                Label("Add a medication", systemImage: "plus").frame(minHeight: 44)
            }
            .tint(theme.color(.info))
            .accessibilityIdentifier("onboarding.addMedication")
        }
    }
}

/// Board 11 — "How careful should it be?". Selection uses `.info` (the accent), never a verdict
/// colour (XC rule 6); the board's green "Recommended" chip follows the accent too.
struct OnboardingGateStep: View {
    @Bindable var model: OnboardingViewModel
    private let theme = JITheme.native
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepTitle(title: OnboardingCopy.gateTitle, subtitle: OnboardingCopy.gateSubtitle)
            ForEach(GatePreset.allCases, id: \.self) { p in
                Button { model.preset = p } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: model.preset == p ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(model.preset == p ? theme.color(.info) : theme.color(.muted))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(p.title).jiFont(.body, weight: .bold).foregroundStyle(theme.color(.text))
                                if p == .balanced {
                                    Text("Recommended").jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.info))
                                }
                            }
                            Text(p.boardDescription).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .background(theme.color(.surface), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(model.preset == p ? theme.color(.info) : theme.color(.hairlineOuter), lineWidth: model.preset == p ? 2 : 1))
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.pressableScale)
                .accessibilityAddTraits(model.preset == p ? .isSelected : [])
                .accessibilityIdentifier("onboarding.preset.\(p.rawValue)")
            }
        }
    }
}
