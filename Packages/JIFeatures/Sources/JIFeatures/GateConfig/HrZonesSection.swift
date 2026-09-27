import SwiftUI
import JICore
import JIDesign

/// B-57 W4 (Toby 2026-09-24): the user's own zones. Enter max HR or LTHR → five floors from the
/// threshold-anchored model; each floor editable; "Avoid Zone 5" is an optional toggle. No zones
/// are assumed: until the user enters a number the section says so.
struct HrZonesSection: View {
    @Bindable var model: GateConfigViewModel
    @State private var anchor: HrZoneAnchor = .maxHr
    @State private var anchorText = ""
    @State private var editingZone: Int?
    @State private var floorText = ""
    @State private var error: String?
    @Environment(\.jiTheme) private var theme

    var body: some View {
        Section {
            if let zones = model.gateSettings.zones {
                ForEach(1...5, id: \.self) { z in
                    Button {
                        editingZone = z; floorText = String(zones.floorsBpm[z - 1]); error = nil
                    } label: {
                        JIChevronRow {
                            Text("Zone \(z)").font(.subheadline).foregroundStyle(theme.color(.text))
                            Spacer()
                            Text("\(zones.rangeText(z)) bpm").font(.subheadline).foregroundStyle(theme.color(.muted))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Moves the lower edge of Zone \(z)")
                    .accessibilityIdentifier("gateConfig.zone\(z)")
                }
                Text("From your \(zones.anchor == .maxHr ? "max heart rate" : "lactate threshold HR") \(zones.anchorBpm). Tap a zone to move its lower edge.")
                    .font(.caption2).foregroundStyle(theme.color(.muted))
                Toggle(isOn: Binding(get: { model.gateSettings.avoidZone5 },
                                     set: { on in Task { await model.setAvoidZone5(on) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Avoid Zone 5").font(.subheadline).foregroundStyle(theme.color(.text))
                        Text("Sessions and Watch workouts stay below \(zones.floorsBpm[4]) bpm.")
                            .font(.caption2).foregroundStyle(theme.color(.muted))
                    }
                }
                .tint(theme.color(.info))
                .accessibilityIdentifier("gateConfig.avoidZone5")
                Button("Clear my zones", role: .destructive) { Task { await model.clearZones() } }
                    .accessibilityIdentifier("gateConfig.clearZones")
            } else {
                Picker("Work them out from", selection: $anchor) {
                    ForEach(HrZoneAnchor.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .tint(theme.color(.info))
                HStack {
                    TextField("bpm", text: $anchorText)
                        .numberPadKeyboard()
                        .accessibilityLabel("\(anchor.title) in bpm")
                        .accessibilityIdentifier("gateConfig.zoneAnchor")
                    Button("Work out zones") {
                        Task { error = await model.setZones(anchor: anchor, bpmText: anchorText) ? nil : hrCapParseError }
                    }
                    .buttonStyle(.borderless)
                    .tint(theme.color(.info))
                    .accessibilityIdentifier("gateConfig.workOutZones")
                }
                Text("No zones yet. JI never assumes yours.").font(.caption2).foregroundStyle(theme.color(.muted))
            }
            if let error { Text(error).font(.footnote).foregroundStyle(theme.color(.danger)) }
        } header: {
            Text("Your heart-rate zones")
        }
        .alert("Zone \(editingZone ?? 0) starts at", isPresented: Binding(get: { editingZone != nil }, set: { if !$0 { editingZone = nil } })) {
            TextField("bpm", text: $floorText)
            Button("Save") {
                let z = editingZone ?? 0
                Task {
                    error = await model.editZone(z, floorText: floorText) ? nil : "Each zone must start above the one below it."
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
