import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import JIDesign

// W5b-L5 (P-export). Port of `mobile/app/export.tsx`: the info header, four checkbox rows (B-57 W1: Mind = check-ins + events) with
// live counts (every row starts unchecked — nothing exports until ticked), and the two share
// actions. RN writes a cache file and calls `Sharing.shareAsync`; the Swift counterpart is a
// `ShareLink` over a lazily-serialized `Transferable` (the system share sheet, no file-access
// entitlement, and nothing is written until the user picks a destination).

public nonisolated let exportHeaderCopy = "A readable copy of what you pick, as CSV or JSON. To move to a new phone, use Backup."

/// B-57 W1: four rows (Mind = check-ins + events), matching Backup's "Journal · Mind · Goals".
public nonisolated enum ExportRow: String, CaseIterable, Sendable {
    case journal, mind, who5, goals
    public var types: [ExportType] {
        switch self { case .journal: [.journal]; case .mind: [.checkins, .events]; case .who5: [.who5]; case .goals: [.goals] }
    }
    public var label: String { self == .mind ? "Mind" : types[0].label }
    public var caption: String { self == .mind ? "Check-ins and events" : types[0].caption }
}

public nonisolated func exportRowSelected(_ row: ExportRow, isSelected: (ExportType) -> Bool) -> Bool { row.types.allSatisfy(isSelected) }

public nonisolated func exportRowToggles(_ row: ExportRow, isSelected: (ExportType) -> Bool) -> [ExportType] {
    exportRowSelected(row, isSelected: isSelected) ? row.types : row.types.filter { !isSelected($0) }
}

public struct ExportView: View {
    @Environment(\.jiTheme) private var theme
    @State private var model: ExportViewModel

    public init(model: ExportViewModel) { _model = State(initialValue: model) }

    public var body: some View {
        List {
            Section {
                ForEach(ExportRow.allCases, id: \.self) { checkboxRow($0) }
            } header: {
                Text("What to export · \(ExportRow.allCases.filter { exportRowSelected($0, isSelected: model.isSelected) }.count) of 4")
            } footer: {
                Text(exportHeaderCopy)
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
    /// B-57 W1: one row per `ExportRow`; the Mind row flips check-ins and events as one.
    private func checkboxRow(_ row: ExportRow) -> some View {
        let selected = exportRowSelected(row, isSelected: model.isSelected)
        return Toggle(isOn: Binding(
            get: { exportRowSelected(row, isSelected: model.isSelected) },
            set: { _ in for t in exportRowToggles(row, isSelected: model.isSelected) { model.toggle(t) } }
        )) {
            JIRow(title: row.label, subtitle: row.caption) {
                Text(model.isLoading ? "…" : "\(row.types.map(model.count).reduce(0, +))").jiFont(.caption)
                    .accessibilityIdentifier("export.count.\(row.rawValue)")
            }
        }
        .tint(theme.color(.info))
        .accessibilityLabel(row.label)
        .accessibilityValue(selected ? "checked" : "unchecked")
        .accessibilityIdentifier("export.checkbox.\(row.rawValue)")
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
