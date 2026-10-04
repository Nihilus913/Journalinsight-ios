import SwiftUI
import JICore
import JIDesign
#if canImport(UIKit)
import UIKit
#endif

// W-B96 C-4 (B-96, BP-24 mockup frames 02/03/05): Settings › Haptics & notifications › Calendar,
// directly under Reminders. One toggle (off by default), a status tag, the "Next 7 days" preview
// and copy that says exactly what it does: one way, write-only, all-day.
public struct CalendarSection: SettingsSection {
    public static let sectionId = "b96.calendar"
    public let id = Self.sectionId
    public let title = "Calendar"
    public let systemImage = "calendar"
    public let sortKey = SettingsSortKey.data + 11
    public let group = SettingsGroupId.haptics
    public init() {}
    public var body: some View { CalendarSectionRows() }
}

public nonisolated let calendarExportCaption =
    "Adds your planned sessions for the next 14 days to your iPhone calendar as all-day events. One way: JournalInsight only adds events and never reads your calendar; edits there do not change the plan."
public nonisolated let calendarExportDeniedCopy =
    "Calendar access is off. Turn on Add Events Only in iOS Settings › JournalInsight › Calendars, then switch this on again."

/// The status tag next to the toggle. nil = nothing to say (off, never asked).
public nonisolated func calendarExportStatus(_ state: CalendarExportModel.State, written: Int, zone: TimeZone) -> String? {
    switch state {
    case .off: return nil
    case .denied: return "access off"
    case .noWeek: return "no plan week yet"
    case .writing(let done, let total): return "writing… \(done) of \(total)"
    case .synced(_, let at):
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB"); f.timeZone = zone; f.dateFormat = "HH:mm"
        return "\(written) added · \(f.string(from: at))"
    }
}

private struct CalendarSectionRows: View {
    @Environment(SettingsViewModel.self) private var settings
    var body: some View {
        if let model = settings.calendarExport {
            CalendarExportRows(model: model)
        } else {
            // rule 5: never a silently missing row (previews / tests without the App wiring).
            SettingsRowGroup(header: "Calendar") {
                SettingsLinkLabel(title: "Planned sessions in Calendar", subtitle: "Not available in this build", systemImage: "calendar")
                    .accessibilityIdentifier("settings.calendar.unavailable")
            }
        }
    }
}

struct CalendarExportRows: View {
    let model: CalendarExportModel
    @Environment(\.jiTheme) private var theme
    @State private var busy = false

    var body: some View {
        SettingsRowGroup(header: "Calendar") {
            Toggle(isOn: Binding(get: { model.enabled }, set: { on in
                busy = true
                Task { await model.setEnabled(on); busy = false }
            })) {
                SettingsLinkLabel(title: "Planned sessions in Calendar", subtitle: "Write-only · one way · all-day",
                                  systemImage: "calendar",
                                  trailing: calendarExportStatus(model.state, written: model.writtenCount, zone: DayKey.zone))
            }
            .tint(theme.color(.info))
            .disabled(busy)
            .accessibilityIdentifier("settings.calendar.enabled")

            if model.state == .denied {
                Text(calendarExportDeniedCopy).jiFont(.caption, tint: .muted)
                    .accessibilityIdentifier("settings.calendar.denied")
                #if canImport(UIKit)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .accessibilityIdentifier("settings.calendar.openSettings")
                #endif
            } else {
                Text(calendarExportCaption).jiFont(.caption, tint: .muted)
                    .accessibilityIdentifier("settings.calendar.caption")
            }
        }
        SettingsRowGroup(header: "Next 7 days") {
            if model.preview.isEmpty {
                Text("No plan week cached yet. The week is read from the planner once it has synced.")
                    .jiFont(.caption, tint: .muted)
                    .accessibilityIdentifier("settings.calendar.preview.empty")
            } else {
                ForEach(model.preview) { day in
                    HStack {
                        Text(calendarPreviewDate(day.date)).jiFont(.caption, tint: .muted).monospacedDigit()
                            .frame(width: 56, alignment: .leading)
                        Text(day.title).jiFont(.body, tint: day.isRest ? .muted : .text)
                        Spacer()
                        Text(day.isRest ? "not written" : "all-day").jiFont(.caption, tint: .muted)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("settings.calendar.preview.\(day.date)")
                }
            }
        }
        .task { await model.load() }
    }
}

/// "Mon 5" for a preview row.
nonisolated func calendarPreviewDate(_ iso: String) -> String {
    guard let d = DayKey(iso: iso) else { return iso }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_GB"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "EEE d"
    return f.string(from: d.startDate(in: TimeZone(identifier: "UTC")!))  // re-prints a yyyy-MM-dd day key; UTC on both sides by design
}
