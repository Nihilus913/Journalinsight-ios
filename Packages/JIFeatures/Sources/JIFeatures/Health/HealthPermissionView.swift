import SwiftUI
import JICore
import JIDesign
import JIHealthKit
#if canImport(UIKit)
import UIKit
#endif

/// Permission UX + T2-gated tiles for the HealthKit read path (W2d, L3). Renders each of
/// `HKPermission`'s three states with honest copy, and gates the Garmin/Firstbeat-only tiles
/// (Body Battery, Garmin sleep score, training readiness, pre-iOS-27 HRV RMSSD) that Apple
/// Watch can't supply, via the shared `EAGatedTile` idiom (rule 5: never a bare zero).
public struct HealthPermissionView: View {
    @Environment(\.jiTheme) private var theme
    let model: HealthPermissionViewModel

    public init(model: HealthPermissionViewModel) {
        self.model = model
    }

    public var body: some View {
        // Rendered inside the caller's `List` section (Settings › Connection), so these are
        // plain rows — the section's own header/footer is the caller's (§2b.2).
        Group {
            statusText
            Button(model.connectLabel) { Task { await model.connect() } }
                .accessibilityIdentifier("health-connect")
                .accessibilityHint(healthConnectHint(decided: model.isDecided))

            // §8.1: the gated tiles reflow 2-up instead of stacking one per line.
            Columns(minimum: 160) {
                ForEach(healthSourceGatedLabels(capabilities: model.appleWatchCapabilities), id: \.self) { label in
                    EAGatedTile(label: label, reason: "Not available on this source")
                }
            }
        }
        .task { model.adoptArrival(healthKitLastUploadDate()) }
    }

    private var statusText: some View {
        Text(HealthPermissionViewModel.statusCopy(for: model.permission))
            .jiFont(.footnote)
            .foregroundStyle(model.permission == .granted ? theme.color(.go) : theme.color(.muted))
            .accessibilityIdentifier("health-permission-status")
    }
}

/// W-DATA R3 (DEV-14): the metrics Apple Watch genuinely cannot supply — Garmin's Body Battery,
/// and HRV (RMSSD) before the iOS 27 type exists. Readiness and Sleep score are NEVER here: JI
/// computes its own readiness from Apple signals and the hub scores an Apple night
/// (`garminSleepScore` / `trainingReadiness` are Garmin's own scores, not those).
nonisolated func healthSourceGatedLabels(capabilities: DataCapability) -> [String] {
    [(DataCapability.bodyBattery, "Body Battery"), (.hrvRMSSD, "HRV (RMSSD)")]
        .filter { !capabilities.contains($0.0) }.map(\.1)
}

nonisolated func healthConnectHint(decided: Bool) -> String {
    decided ? "Opens Apple Health, where read access is changed (Sharing › Apps)."
            : "Asks iOS for permission to read Apple Health data."
}

// MARK: - B-57 W1 r4 board layout (fixer g3, board 5/09)

/// One row of the board's "JI WILL READ" list.
nonisolated struct HealthReadRow: Sendable, Equatable, Identifiable {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: JIColorRole
    let status: BoardStatus
    var id: String { title }
}

/// What JI reads from Apple Health and whether it can. HealthKit never confirms a read grant, so
/// "Read" means access was answered (JI then sees data after the first sync). Workouts are on the
/// board but no read path ships yet, so that row says so instead of claiming it.
nonisolated func healthReadRows(permission: HKPermission, capabilities: DataCapability) -> [HealthReadRow] {
    let status: BoardStatus = switch permission {
    case .granted: BoardStatus(word: "Read", systemImage: "checkmark", role: .go)
    case .denied: BoardStatus(word: "Declined", systemImage: "exclamationmark.triangle", role: .danger)
    case .notDetermined: BoardStatus(word: "Not asked", systemImage: "minus", role: .muted)
    }
    let hrvSubtitle = capabilities.contains(.hrvRMSSD) ? "RMSSD, the gate signal" : "SDNN until RMSSD is in Health"
    return [
        HealthReadRow(title: "Overnight HRV", subtitle: hrvSubtitle, systemImage: "waveform.path", tint: .reduced, status: status),
        HealthReadRow(title: "Sleep", subtitle: "Duration and stages", systemImage: "moon", tint: .info, status: status),
        HealthReadRow(title: "Resting HR", subtitle: "Overnight only", systemImage: "heart", tint: .danger, status: status),
        HealthReadRow(title: "Workouts", subtitle: "Feeds training load", systemImage: "dumbbell", tint: .muted,
                      status: BoardStatus(word: "Not read yet", systemImage: "minus", role: .muted)),
    ]
}

// MARK: - W-GUI M6 (mockup 47): arrival-based status, pure

/// "Connected · 12:40" when the uploader has a 2xx time (data ARRIVED); else "No data yet" —
/// never "Declined" (iOS does not report read permissions, DEV-12). The permission-based
/// `healthReadRows` stays for the connect flow; the settings screen draws THIS.
nonisolated func healthArrivalStatus(lastUpload: Date?, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> BoardStatus {
    guard let lastUpload else { return BoardStatus(word: "No data yet", systemImage: "minus", role: .muted) }
    let c = calendar.dateComponents([.day, .month, .hour, .minute], from: lastUpload)
    let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    let word = calendar.isDate(lastUpload, inSameDayAs: now)
        ? "Connected · \(time)"
        : "Connected · \(c.day ?? 0) \(calendar.shortMonthSymbols[((c.month ?? 1) - 1) % 12]) \(time)"
    return BoardStatus(word: word, systemImage: "checkmark", role: .go)
}

/// W-DATA R2 (DEV-12): when each "JI reads" row's own types last arrived at the hub.
nonisolated struct HealthReadArrivals: Sendable, Equatable {
    var hrv: Date?, sleep: Date?, restingHR: Date?
}

/// Per-type arrival from the uploader's App-Group records (`JIHealthKit.HealthKitArrival`).
nonisolated func healthReadArrivals(_ record: UserDefaults? = UserDefaults(suiteName: "group.toby913.JournalInsight")) -> HealthReadArrivals {
    HealthReadArrivals(hrv: HealthKitArrival.lastUpload(for: [.hrvRMSSD, .hrvSDNN], in: record),
                       sleep: HealthKitArrival.lastUpload(for: [.sleepAnalysis], in: record),
                       restingHR: HealthKitArrival.lastUpload(for: [.restingHeartRate], in: record))
}

/// The "JI reads" rows with the arrival-based status on the read types; Workouts keep their
/// honest "Not read yet" (no read path ships yet).
nonisolated func healthReadRowsArrival(capabilities: DataCapability, lastUpload: Date?, now: Date = Date()) -> [HealthReadRow] {
    healthReadRowsArrival(capabilities: capabilities,
                          arrivals: HealthReadArrivals(hrv: lastUpload, sleep: lastUpload, restingHR: lastUpload), now: now)
}

/// DEV-12: each row's status keys off ITS type's last upload — never a permission lookup.
nonisolated func healthReadRowsArrival(capabilities: DataCapability, arrivals: HealthReadArrivals, now: Date = Date()) -> [HealthReadRow] {
    let byTitle = ["Overnight HRV": arrivals.hrv, "Sleep": arrivals.sleep, "Resting HR": arrivals.restingHR]
    return healthReadRows(permission: .notDetermined, capabilities: capabilities).map { row in
        guard let arrival = byTitle[row.title] else { return row }
        return HealthReadRow(title: row.title, subtitle: row.subtitle, systemImage: row.systemImage, tint: row.tint,
                             status: healthArrivalStatus(lastUpload: arrival, now: now))
    }
}

/// The "Computed from these" tiles (mockup 47): Readiness "— · Calibrating" (W3), Sleep score
/// "— · hub, Apple night" (present only when the hub sent one), Body Battery "— · Garmin only"
/// (true: never for Readiness or Sleep score, report §7 rule 6).
public nonisolated struct HealthComputedTile: Equatable, Sendable, Identifiable {
    public let id: String, title: String, value: String, note: String
}
public nonisolated func healthComputedTiles(sleepScore: Double?) -> [HealthComputedTile] {
    [
        HealthComputedTile(id: "readiness", title: "Readiness", value: "—", note: JIMissingReason.calibrating.rawValue),
        HealthComputedTile(id: "sleep", title: "Sleep score", value: sleepScore.map { jiNumber($0, 0) } ?? "—", note: "hub, Apple night"),
        HealthComputedTile(id: "bodyBattery", title: "Body Battery", value: "—", note: "Garmin only"),
    ]
}
public nonisolated let healthArrivalCaption = "\u{201C}Connected\u{201D} means data arrived; iOS does not report read permissions. Apple\u{2019}s own Readiness score is not shared with apps: JI computes its own from the same signals. To change access: Settings \u{203A} Health \u{203A} Sharing \u{203A} Apps."

/// The board's "Connect Apple Health" layout as `List` sections: header (icon, why), the
/// "JI will read" list, "Not on this source" tiles, and the CTA — wired to the existing HealthKit
/// authorisation request (`HealthPermissionViewModel.connect()`).
public struct HealthPermissionBoardSections: View {
    @Environment(\.jiTheme) private var theme
    let model: HealthPermissionViewModel
    /// true = draw the big "Connect Apple Health" title inside the list (the standalone screen).
    var showsTitle: Bool = true

    public init(model: HealthPermissionViewModel, showsTitle: Bool = true) {
        self.model = model
        self.showsTitle = showsTitle
    }


    /// W-GUI M6: the uploader's last 2xx time (the PF-04 instant), read once per body.
    private var lastUpload: Date? { healthKitLastUploadDate() }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "heart")
                    .font(.title2)
                    .foregroundStyle(theme.color(.danger))
                    .frame(width: 48, height: 48)
                    .background(theme.color(.surface2), in: RoundedRectangle(cornerRadius: theme.radius(.nested), style: .continuous))
                    .accessibilityHidden(true)
                if showsTitle {
                    Text("Connect Apple Health").jiFont(.title, weight: .heavy, tint: .text).accessibilityAddTraits(.isHeader)
                }
                Text("Your Watch nights decide Full, Modified or Rest.").jiFont(.body, tint: .muted)
                // W-GUI M6 (mockup 47): the header status is arrival-based (DEV-12 logic stays W-REG2).
                let header = healthArrivalStatus(lastUpload: lastUpload)
                BoardStatusLabel(word: header.word, systemImage: header.systemImage ?? "minus", role: header.role)
                    .accessibilityIdentifier("health.arrival")
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
            .task {
                model.adoptArrival(lastUpload)
                await model.refreshComputed()
            }
        }
        Section("JI reads") {
            ForEach(healthReadRowsArrival(capabilities: model.appleWatchCapabilities, arrivals: healthReadArrivals())) { row in
                SettingsLinkLabel(title: row.title, subtitle: row.subtitle, systemImage: row.systemImage,
                                  badge: row.status, tint: theme.color(row.tint))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("health.read.\(row.title)")
            }
        }
        Section("Computed from these") {
            Columns(minimum: 96, spacing: JISpacing.tileGap, tileHeight: .tile) {
                ForEach(healthComputedTiles(sleepScore: model.sleepScore)) { tile in
                    JITile(family: .tile) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile.title).jiFont(.caption, tint: .muted)
                            Text(tile.value).jiNumeral(.numeralSmall, tint: tile.value == "—" ? .muted : .text)
                            Text(tile.note).jiFont(.micro, tint: .muted).lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(tile.title): \(tile.value == "—" ? "no value" : tile.value), \(tile.note)")
                    .accessibilityIdentifier("health.computed.\(tile.id)")
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        Section {
            VStack(alignment: .leading, spacing: JISpacing.s2) {
                // ONE primary (connect) and a secondary (open Health settings) — report §7. DEV-12:
                // once decided iOS never re-prompts, so the primary itself opens Health settings
                // and the (now duplicate) secondary is dropped.
                Button { Task { await model.connect() } } label: { Text(model.connectLabel) }
                .buttonStyle(.jiPrimary)
                .accessibilityIdentifier("health-connect")
                .accessibilityHint(healthConnectHint(decided: model.isDecided))
                if !model.isDecided {
                    Button { HealthPermissionViewModel.openHealthSettingsOnDevice() } label: {
                        Text("Open Health settings")
                    }
                    .buttonStyle(.jiSecondary)
                    .accessibilityIdentifier("health-open-settings")
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if model.permission != .notDetermined {
                    Text(HealthPermissionViewModel.statusCopy(for: model.permission))
                        .accessibilityIdentifier("health-permission-status")
                }
                Text(healthArrivalCaption).accessibilityIdentifier("health.caption")
            }
        }
    }
}

/// The standalone board screen (registry entry "Health permission").
public struct HealthPermissionScreen: View {
    let model: HealthPermissionViewModel
    public init(model: HealthPermissionViewModel) { self.model = model }
    public var body: some View {
        List { HealthPermissionBoardSections(model: model) }
            .jiNativeFormChrome()
            .scrollContentBackground(.hidden)   // W-GUI M6
            .jiPageGround()
            .jiGlassBackButton()
            .jiTheme(.native)
    }
}
