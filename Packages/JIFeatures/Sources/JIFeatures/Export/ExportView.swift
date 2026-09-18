import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import JIDesign

// W5b-L5 (P-export). Port of `mobile/app/export.tsx`: the info header, five checkbox rows with
// live counts (every row starts unchecked — nothing exports until ticked), and the two share
// actions. RN writes a cache file and calls `Sharing.shareAsync`; the Swift counterpart is a
// `ShareLink` over a lazily-serialized `Transferable` (the system share sheet, no file-access
// entitlement, and nothing is written until the user picks a destination).
public struct ExportView: View {
    @State private var model: ExportViewModel

    public init(model: ExportViewModel) { _model = State(initialValue: model) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pick what to include, then share it to Files, email, or another app. Export is plaintext regardless of on-device encryption — nothing is included until you tick it.")
                    .font(.footnote).foregroundStyle(JIColor.muted)
                    .accessibilityIdentifier("export.info")
                selectionCard
                actions
                if let error = model.errorMessage {
                    Surface {
                        Text(error).font(.footnote).foregroundStyle(JIColor.danger)
                            .accessibilityIdentifier("export.error")
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
        }
        .background(JIColor.bg)
        .navigationTitle("Export")
        .onAppear { model.load() }
    }

    private var selectionCard: some View {
        Surface(radius: JIRadius.hero, padding: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What to export")
                    .font(.caption2.weight(.bold)).textCase(.uppercase).foregroundStyle(JIColor.muted)
                ForEach(ExportType.allCases, id: \.self) { checkboxRow($0) }
            }
        }
    }

    /// RN `CheckboxRow` — `accessibilityRole="checkbox"` + `accessibilityState={{ checked }}`.
    private func checkboxRow(_ type: ExportType) -> some View {
        let checked = model.isSelected(type)
        // Press-in haptic + 0.92 scale come from `.pressableScale` (rule 7), same as every row.
        return Button { model.toggle(type) } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(checked ? JIColor.info : JIColor.muted, lineWidth: 2)
                        .background(checked ? JIColor.info : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .frame(width: 22, height: 22)
                    if checked {
                        Image(systemName: "checkmark").font(.caption.weight(.black)).foregroundStyle(JIColor.bg)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.label).font(.subheadline.weight(.bold)).foregroundStyle(JIColor.text)
                    Text(type.caption).font(.caption2).foregroundStyle(JIColor.muted)
                }
                Spacer()
                Text(model.isLoading ? "…" : "\(model.count(type))")
                    .font(.caption).foregroundStyle(JIColor.muted)
                    .accessibilityIdentifier("export.count.\(type.rawValue)")
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableScale)
        .accessibilityLabel(type.label)
        .accessibilityValue(checked ? "checked" : "unchecked")
        .accessibilityAddTraits(checked ? [.isSelected] : [])
        .accessibilityIdentifier("export.checkbox.\(type.rawValue)")
    }

    private var actions: some View {
        VStack(spacing: 10) {
            ShareLink(
                item: CSVExportPayload(text: model.payload(.csv)),
                preview: SharePreview(ExportFormat.csv.filename)
            ) {
                actionLabel("Export as CSV")
            }
            .buttonStyle(.pressableScale)
            .disabled(!model.anySelected || model.isLoading)
            .accessibilityLabel("Export as CSV")
            .accessibilityIdentifier("export.csv")

            ShareLink(
                item: JSONExportPayload(text: model.payload(.json)),
                preview: SharePreview(ExportFormat.json.filename)
            ) {
                actionLabel("Export as JSON")
            }
            .buttonStyle(.pressableScale)
            .disabled(!model.anySelected || model.isLoading)
            .accessibilityLabel("Export as JSON")
            .accessibilityIdentifier("export.json")

            if !model.anySelected {
                Text("Tick at least one type above to enable export.")
                    .font(.caption2).foregroundStyle(JIColor.muted)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("export.hint")
            }
        }
    }

    private func actionLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(JIColor.bg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(JIColor.info, in: RoundedRectangle(cornerRadius: JIRadius.card))
            .opacity(model.anySelected ? 1 : 0.5)
    }
}

// MARK: - Transferable payloads
//
// One `Transferable` per format because the exported content type is part of the static
// representation. The bytes are already serialized (memoized on the model), so sharing is a copy,
// never a second pass over the database.

nonisolated struct CSVExportPayload: Transferable, Sendable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { payload in Data(payload.text.utf8) }
            .suggestedFileName(ExportFormat.csv.filename)
    }
}

nonisolated struct JSONExportPayload: Transferable, Sendable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { payload in Data(payload.text.utf8) }
            .suggestedFileName(ExportFormat.json.filename)
    }
}
