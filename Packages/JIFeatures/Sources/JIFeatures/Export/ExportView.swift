import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import JIDesign

// W5b-L5 (P-export). Port of `mobile/app/export.tsx`: the info header, four checkbox rows (B-57 W1: Mind = check-ins + events) with
// live counts (W-FIX3 BUG-45: board 5/04 opens with Journal, Mind and WHO-5 ticked), and the two share
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

/// W-FIX3 BUG-45 (board 5/04): the rows ticked when the screen opens — Journal, Mind, WHO-5
/// (Goals stays off). Nothing leaves the phone until the user taps Export, so a pre-tick is safe.
public nonisolated let exportDefaultRows: [ExportRow] = [.journal, .mind, .who5]

/// Ticks `exportDefaultRows` on a model nobody has touched yet; a user's choice is never overwritten.
@MainActor public func exportApplyBoardDefaults(_ model: ExportViewModel) {
    guard !model.anySelected else { return }
    for row in exportDefaultRows {
        for t in exportRowToggles(row, isSelected: model.isSelected) { model.toggle(t) }
    }
}

/// Board 5/04 line under the rows.
public nonisolated func exportTickedLine(_ ticked: Int) -> String {
    "\(ticked) of \(ExportRow.allCases.count) ticked. Nothing leaves the phone unless you tick it."
}

public struct ExportView: View {
    @Environment(\.jiTheme) private var theme
    @State private var model: ExportViewModel
    @State private var appliedDefaults = false

    public init(model: ExportViewModel) { _model = State(initialValue: model) }

    public var body: some View {
        List {
            // Board 5/04: the copy sits under the title, above the rows.
            Section {
                Text(exportHeaderCopy)
                    .jiFont(.subheadline, tint: .muted)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                    .accessibilityIdentifier("export.info")
            }

            Section {
                ForEach(ExportRow.allCases, id: \.self) { checkboxRow($0) }
            } header: {
                Text("What to export")
            } footer: {
                Text(exportTickedLine(tickedCount))
                    .accessibilityIdentifier("export.hint")
            }

            Section {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { csvButton; jsonButton.fixedSize() }
                    VStack(spacing: 12) { csvButton; jsonButton }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
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
        .onAppear {
            if !appliedDefaults { appliedDefaults = true; exportApplyBoardDefaults(model) }
            model.load()
        }
    }

    private var tickedCount: Int {
        ExportRow.allCases.filter { exportRowSelected($0, isSelected: model.isSelected) }.count
    }

    /// Board 5/04: the accent-filled primary. `.info` is the user's accent (`JIAccent`).
    private var csvButton: some View {
        ShareLink(
            item: CSVExportPayload(text: model.payload(.csv)),
            preview: SharePreview(ExportFormat.csv.filename)
        ) {
            Text("Export as CSV").jiFont(.body, weight: .bold).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .tint(theme.color(.info))
        .disabled(!model.anySelected || model.isLoading)
        .accessibilityLabel("Export as CSV")
        .accessibilityIdentifier("export.csv")
    }

    private var jsonButton: some View {
        ShareLink(
            item: JSONExportPayload(text: model.payload(.json)),
            preview: SharePreview(ExportFormat.json.filename)
        ) {
            Text("JSON").jiFont(.body, weight: .semibold).frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .tint(theme.color(.text))
        .disabled(!model.anySelected || model.isLoading)
        .accessibilityLabel("Export as JSON")
        .accessibilityIdentifier("export.json")
    }

    /// RN `CheckboxRow`. W-FIX3 BUG-45 (board 5/04): a tick circle in the user's accent, not a
    /// switch; the whole row is the tap target. The Mind row flips check-ins and events as one.
    private func checkboxRow(_ row: ExportRow) -> some View {
        let selected = exportRowSelected(row, isSelected: model.isSelected)
        return Button {
            for t in exportRowToggles(row, isSelected: model.isSelected) { model.toggle(t) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? theme.color(.info) : theme.color(.muted))
                    .accessibilityHidden(true)
                JIRow(title: row.label, subtitle: row.caption) {
                    Text(model.isLoading ? "…" : "\(row.types.map(model.count).reduce(0, +))").jiFont(.caption)
                        .accessibilityIdentifier("export.count.\(row.rawValue)")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.label)
        .accessibilityValue(selected ? "checked" : "unchecked")
        .accessibilityAddTraits(selected ? [.isToggle, .isSelected] : .isToggle)
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
