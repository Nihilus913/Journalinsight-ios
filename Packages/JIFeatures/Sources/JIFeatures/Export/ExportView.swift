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
    @Environment(\.jiTheme) private var theme
    @State private var model: ExportViewModel

    public init(model: ExportViewModel) { _model = State(initialValue: model) }

    public var body: some View {
        List {
            Section {
                ForEach(ExportType.allCases, id: \.self) { checkboxRow($0) }
            } header: {
                Text("What to export")
            } footer: {
                Text("Pick what to include, then share it to Files, email, or another app. Export is plaintext regardless of on-device encryption — nothing is included until you tick it.")
                    .accessibilityIdentifier("export.info")
            }

            Section {
                ShareLink(
                    item: CSVExportPayload(text: model.payload(.csv)),
                    preview: SharePreview(ExportFormat.csv.filename)
                ) {
                    Text("Export as CSV").frame(maxWidth: .infinity)
                }
                .disabled(!model.anySelected || model.isLoading)
                .accessibilityLabel("Export as CSV")
                .accessibilityIdentifier("export.csv")

                ShareLink(
                    item: JSONExportPayload(text: model.payload(.json)),
                    preview: SharePreview(ExportFormat.json.filename)
                ) {
                    Text("Export as JSON").frame(maxWidth: .infinity)
                }
                .disabled(!model.anySelected || model.isLoading)
                .accessibilityLabel("Export as JSON")
                .accessibilityIdentifier("export.json")
            } footer: {
                if !model.anySelected {
                    Text("Tick at least one type above to enable export.")
                        .accessibilityIdentifier("export.hint")
                }
            }

            if let error = model.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(theme.color(.danger))
                        .accessibilityIdentifier("export.error")
                }
            }
        }
        .jiNativeFormChrome()
        .readableColumn()
        .jiTheme(.native)
        .navigationTitle("Export")
        .onAppear { model.load() }
    }

    /// RN `CheckboxRow` — B-33 §2b.2: a `Toggle` in a `List` row, so the checkbox, the 44-pt
    /// height and the checked state all come from the system.
    private func checkboxRow(_ type: ExportType) -> some View {
        Toggle(isOn: Binding(get: { model.isSelected(type) }, set: { _ in model.toggle(type) })) {
            JIRow(title: type.label, subtitle: type.caption) {
                Text(model.isLoading ? "…" : "\(model.count(type))").jiFont(.caption)
                    .accessibilityIdentifier("export.count.\(type.rawValue)")
            }
        }
        .tint(theme.color(.info))
        .accessibilityLabel(type.label)
        .accessibilityValue(model.isSelected(type) ? "checked" : "unchecked")
        .accessibilityIdentifier("export.checkbox.\(type.rawValue)")
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
