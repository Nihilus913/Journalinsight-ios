import SwiftUI
import JIDesign
import JIHealthKit

// W5a-L0: `ConnectionSheet`'s Health sections (W2h backload, W2d Apple Watch read), moved (not
// rewritten) into the registry. Both models are optional on `SettingsViewModel` — nil hides the
// matching section exactly as `ConnectionSheet` does (previews / no HealthKit path wired).
public struct HealthSection: SettingsSection {
    public static let sectionId = "l0.health"
    public let id = Self.sectionId
    public let title = "Apple Health"
    public let systemImage = "heart.text.square"
    public let sortKey = SettingsSortKey.connection + 10
    public let group = SettingsGroupId.health
    public init() {}
    public var body: some View { HealthSectionRows() }
}

private struct HealthSectionRows: View {
    @Environment(SettingsViewModel.self) private var model

    // B-57 W1 r4 (g3): the board's Connect Apple Health layout first; the backload (the other
    // thing this screen always carried) stays below it, unchanged.
    var body: some View {
        if let healthPermissionModel = model.healthPermissionModel {
            HealthPermissionBoardSections(model: healthPermissionModel, showsTitle: false)
        }
        if let backloadModel = model.backloadModel {
            HealthBackloadSection(model: backloadModel)
        }
        if let moodMirror = model.moodMirror {
            MoodMirrorRows(model: moodMirror)
        }
        WorkoutBackfillSection()
    }
}

/// Toby 2026-09-28: how far back Apple workouts are sent to the hub on the first upload.
/// Widening re-sends from the new start (the hub matches by workout id, no duplicates);
/// narrowing never removes what the hub already has.
struct WorkoutBackfillSection: View {
    private let defaults = UserDefaults(suiteName: HealthKitUploader.appGroupSuite)
    @State private var choice: WorkoutBackfill = .default

    var body: some View {
        Section {
            Picker("Send workouts from the last", selection: $choice) {
                ForEach(WorkoutBackfill.allCases) { Text($0.label).tag($0) }
            }
            .accessibilityIdentifier("settings-workout-backfill")
            .onChange(of: choice) { _, new in WorkoutBackfill.set(new, defaults: defaults) }
        } header: {
            Text("Apple workouts to the hub")
        } footer: {
            Text("A longer window sends the older workouts on the next sync. A shorter one never removes workouts the hub already has.")
        }
        .onAppear { choice = WorkoutBackfill.current(defaults) }
    }
}

public nonisolated let moodMirrorCaption =
    "Adds your daily check-in mood to Apple Health as State of Mind. One way, from today on: only the mood leaves JournalInsight — never your note, stress, energy or medication."
public nonisolated let moodMirrorDeniedCopy =
    "State of Mind access is off. Allow it in iOS Settings › Health › Data Access › JournalInsight, then switch this on again."

/// B-24 P2: Settings › Apple Health › "Mirror mood to Apple Health" (off by default).
struct MoodMirrorRows: View {
    let model: MoodMirrorSettingsModel
    @Environment(\.jiTheme) private var theme
    @State private var busy = false

    var body: some View {
        SettingsRowGroup(header: "Mood") {
            Toggle(isOn: Binding(get: { model.enabled }, set: { on in
                busy = true
                Task { await model.setEnabled(on); busy = false }
            })) {
                SettingsLinkLabel(title: "Mirror mood to Apple Health", subtitle: "Mood only · one way · daily", systemImage: "face.smiling")
            }
            .tint(theme.color(.info))
            .disabled(busy)
            .accessibilityIdentifier("settings.health.moodMirror")

            if model.denied {
                Text(moodMirrorDeniedCopy).jiFont(.caption, tint: .muted)
                    .accessibilityIdentifier("settings.health.moodMirror.denied")
            } else {
                Text(moodMirrorCaption).jiFont(.caption, tint: .muted)
                    .accessibilityIdentifier("settings.health.moodMirror.caption")
            }
            if let error = model.errorMessage {
                Text(error).jiFont(.caption).foregroundStyle(theme.color(.danger))
                    .accessibilityIdentifier("settings.health.moodMirror.error")
            }
        }
    }
}
