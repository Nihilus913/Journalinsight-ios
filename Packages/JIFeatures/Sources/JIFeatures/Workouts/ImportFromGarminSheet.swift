import SwiftUI
import JICore
import JIDesign

/// W-B40 L2 (B-40b-3, spec §4 "ImportFromGarminSheet") — one button, then the hub's report:
/// linked / created / skipped. The hub does the import (the phone never talks to Garmin); it is
/// idempotent, so the button stays available. Hub-only: disabled offline with the reason.
public struct ImportFromGarminSheet: View {
    @Bindable private var model: WorkoutLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var report: GarminImportReport?
    private let theme = JITheme.native

    public init(model: WorkoutLibraryViewModel) { self.model = model }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Import from Garmin")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("garmin-import-done")
                    }
                }
        }
        .jiTheme(.native)
        .jiNativeSheetSizing()
    }

    @ViewBuilder var content: some View {
        List {
            Section {
                Text("Brings in the workouts you built in Garmin Connect. Garmin coach plans are left out. Running it again is safe — nothing is duplicated, and a workout you edited here since the last import is kept as it is.")
                    .foregroundStyle(theme.color(.text))
                Button {
                    Task { report = await model.importFromGarmin() }
                } label: {
                    HStack {
                        Label("Import from Garmin Connect", systemImage: "square.and.arrow.down")
                        Spacer()
                        if model.isImporting { ProgressView() }
                    }
                }
                .disabled(model.isImporting || model.garminDisabledReason != nil)
                .accessibilityIdentifier("garmin-import-run")
            } footer: {
                if let reason = model.garminDisabledReason {
                    Text(reason)
                } else if let notice = model.notice, notice.isError, report == nil {
                    Text(notice.text).foregroundStyle(theme.color(.danger))
                }
            }

            if let report = report ?? model.lastImport {
                Section("Result") {
                    reportRow("Linked", report.linked, symbol: "link")
                    reportRow("Added", report.created, symbol: "plus.circle")
                    reportRow("Skipped", report.skipped, symbol: "pause.circle")
                }
                .accessibilityIdentifier("garmin-import-report")
            }
        }
        .jiNativeFormChrome()
    }

    private func reportRow(_ title: String, _ bucket: ImportBucket, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol).foregroundStyle(theme.color(.text))
            Text(WorkoutFormat.bucket(bucket)).jiFont(.footnote).foregroundStyle(theme.color(.muted))
        }
        .accessibilityElement(children: .combine)
    }
}
