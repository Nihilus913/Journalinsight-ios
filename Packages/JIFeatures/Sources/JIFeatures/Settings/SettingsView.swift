import SwiftUI
import JICore
import JIDesign
import JIHub
import JIHealthKit
import JIPersistence

// W5a-L0 (P-settings seam). FROZEN after L0. The Settings screen is a section registry: this
// view only iterates `model.sections` (see `SettingsSection.swift`); every later lane adds its
// own `Sections/<Area>Section.swift` + one registry line and never touches this file.
// W-B41 (B-41): the screen is now the TOP LEVEL of a two-level menu — one `NavigationLink` per
// `SettingsGroupId`, each pushing a `GroupSettingsView` that renders that group's registry
// sections. Section bodies moved, never rewritten. Presented as a sheet from the `RootTabView`
// gear ("Done" = RN's `DoneButton`).
// B-57 W1 (fixer f3, board 5/01): the root is the board's FLAT list — CONNECTION · PREFERENCES ·
// DATA · ADVANCED. A registry section whose body is a single link row is drawn inline (its rows
// only, `settingsRowsOnly`); a section with its own fields (hub, Health, haptics, Edit Today…)
// sits behind one pushed row. `SettingsRoot.rows` is the one map, and a test pins that every
// registered section stays reachable from it.

// W-TGT fixer 1e (mock 04, spec §4): the root is CONNECTION (Sync & hub · Apple Health) ·
// TODAY (Home & widgets · Targets) · PHONE (Appearance · Haptics & notifications · Reminders) ·
// APP (About & version · Developer, debug only). Sync now and the four data rows moved into
// Sync & hub; the Haptics switch and strength into Haptics & notifications. Every registry
// section stays reachable from one of these rows (a test pins it).

/// The root's four groups (mock 04). `SettingsGroup` stays the sections' sortKey band.
public nonisolated enum SettingsRootGroup: String, CaseIterable, Sendable, Equatable {
    case connection, today, phone, app

    public var title: String {
        switch self {
        case .connection: "Connection"
        case .today: "Today"
        case .phone: "Phone"
        case .app: "App"
        }
    }
}

/// One row (or run of inline rows) on the Settings root.
public nonisolated struct SettingsRootRow: Sendable, Identifiable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The sections' own link rows, drawn straight into the group's card.
        case inline
        /// One row that pushes a screen holding these sections.
        case push(title: String, systemImage: String, placeholder: String?)
        /// Home & widgets (mock 05): its own screen — Cards, On Today, Widgets & Live Activity.
        case homeWidgets
    }
    public let id: String
    public let group: SettingsRootGroup
    public let kind: Kind
    public let sectionIds: [String]
}

public nonisolated enum SettingsRoot {
    public static let rows: [SettingsRootRow] = {
        var rows: [SettingsRootRow] = [
            .init(id: "hub", group: .connection,
                  kind: .push(title: "Sync & hub", systemImage: "arrow.triangle.2.circlepath", placeholder: nil),
                  sectionIds: [SyncNowSection.sectionId, "l0.hub"] + settingsDataSectionIds),
            .init(id: "health", group: .connection, kind: .push(title: "Apple Health", systemImage: "heart", placeholder: nil),
                  sectionIds: ["l0.health"]),
            .init(id: "home", group: .today, kind: .homeWidgets,
                  sectionIds: ["l3.editToday", OnTodaySection.sectionId, "l5.weeklyPlan"]),
            .init(id: "targets", group: .today, kind: .inline, sectionIds: ["l0.preferences"]),
            .init(id: "appearance", group: .phone, kind: .inline, sectionIds: ["l1.appearance"]),
            .init(id: "haptics", group: .phone,
                  kind: .push(title: "Haptics & notifications", systemImage: "iphone.radiowaves.left.and.right", placeholder: nil),
                  sectionIds: ["w8.haptics"]),
            .init(id: "reminders", group: .phone, kind: .inline, sectionIds: ["l2.reminders"]),
            // W-B38-B B-9: the plate calculator's bar + plate pairs.
            .init(id: "plates", group: .phone, kind: .push(title: "Plates & bar", systemImage: "scalemass", placeholder: nil),
                  sectionIds: [PlateInventorySection.sectionId]),
            .init(id: "about", group: .app, kind: .inline, sectionIds: ["l4.version"]),
        ]
        #if DEBUG
        rows.append(.init(id: "developer", group: .app,
                          kind: .push(title: "Developer", systemImage: "hammer", placeholder: nil),
                          sectionIds: ["l3.provider", "ondevice.verdict"]))
        #endif
        return rows
    }()

    /// Mock 04's four headers, in order.
    public static var headers: [String] { SettingsRootGroup.allCases.map(\.title) }
}

/// Sync & hub row (mock 04): the last sync, then what else lives behind it.
public nonisolated func settingsSyncHubSubtitle(lastSync: Date?, now: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
    let rest = "backup, data quality, mirrors, export"
    guard let lastSync else { return "Not synced yet · \(rest)" }
    return "Hub synced \(settingsClock(lastSync, now: now, calendar: calendar)) · \(rest)"
}

/// The Today group's footer (mock 04).
public nonisolated let settingsTodayFooter = "Goals, My KPIs and Gate thresholds were three screens for one thing. Targets is that thing; the square picker lives with the rest of the Home layout."

// MARK: - Trailing values (pure; every one from real state, "—"/nil when unknown)

/// Goals row: "80.2 → 75.0 kg" (hub goal document's base → target), nil until it has loaded.
public nonisolated func settingsGoalsTrailing(_ goals: Goals?) -> String? {
    guard let goals else { return nil }
    let target = jiNumber(goals.weight.targetKg, 1)
    guard let base = goals.weight.baseKg else { return "Target \(target) kg" }
    return "\(jiNumber(base, 1)) → \(target) kg"
}

public nonisolated func settingsKpisTrailing(_ count: Int) -> String {
    count == 0 ? "None chosen" : "\(count) chosen"
}

/// W-FIX6 F6-16: the Reminders row count = the pending requests the Reminders screen reads
/// (`ReminderScheduler.activeCount()`), so the two can never disagree.
public nonisolated func settingsRemindersTrailing(count: Int) -> String {
    count == 0 ? "Off" : "\(count) on"
}

/// Reminders row fallback (no notification centre — host-less tests / offscreen renders): how
/// many daily + workout reminders the saved prefs say are on ("Off" when none).
/// W-FIX5 W4-3: plus the HR-cap re-check when it is scheduled (it lives only as a pending
/// notification, so the caller reads `ReminderScheduler.hrCapCheckDue()`).
public nonisolated func settingsRemindersTrailing(_ prefs: RemindersPrefs?, hrCapCheckOn: Bool = false) -> String {
    let on = (prefs?.daily.values.filter(\.enabled).count ?? 0) + (prefs?.workouts.values.filter(\.enabled).count ?? 0)
        + (hrCapCheckOn ? 1 : 0)
    return on == 0 ? "Off" : "\(on) on"
}

nonisolated private func settingsClock(_ date: Date, now: Date, calendar: Calendar) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_GB")
    f.timeZone = calendar.timeZone
    f.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "d MMM"
    return f.string(from: date)
}

public nonisolated func settingsSyncTrailing(syncing: Bool, failed: Bool, lastSync: Date?, now: Date,
                                             calendar: Calendar = .autoupdatingCurrent) -> String {
    if syncing { return "Syncing…" }
    if failed { return "Sync failed" }
    // W-FIX6 F6-13: the one place the last-sync time is shown (the Hub row no longer repeats it).
    guard let lastSync else { return "Last sync —" }
    return "Last sync \(settingsClock(lastSync, now: now, calendar: calendar))"
}

/// W-FIX6 F6-13: the caption under Sync now sits on the rows' text inset, not on the 4 pt edge
/// of the clear row (where "05:10" was clipped at the left margin).
nonisolated enum SettingsSyncCaption {
    static let leadingInset: CGFloat = 16
}

public nonisolated func settingsHubSubtitle(host: String?, lastSync: Date?, now: Date,
                                            calendar: Calendar = .autoupdatingCurrent) -> String {
    // W-FIX6 F6-13: host only — "· last sync 05:10" wrapped under "✓ Connected" and repeated
    // the Sync now caption. `lastSync` stays in the signature for callers; the caption shows it.
    guard let host, !host.isEmpty else { return "Not set up" }
    _ = (lastSync, now, calendar)
    return host
}

/// W-FIX6 F6-12: the subtitle of a hub-only row (Goals, My KPIs) whose screen could not be built.
/// "Connect to your hub" only when no hub is saved; with a hub saved it names the real reason —
/// on device it was the debug data source set to Apple Watch while the Hub row said Connected.
public nonisolated func settingsHubOnlySubtitle(action: String, hubConfigured: Bool, dataSource: ProviderKind) -> String {
    guard hubConfigured else { return "Connect to your hub to \(action)" }
    switch dataSource {
    case .appleWatch: return "Reads the hub · data source is Apple Watch (Developer)"
    case .hub: return "Hub screen not loaded · reopen Settings"
    }
}

/// Hub badge — only what a connection test said; nil before one ran (never a guessed "Connected").
nonisolated func settingsHubBadge(_ status: ConnectionTestResult?, testing: Bool) -> BoardStatus? {
    if testing { return BoardStatus(word: "Checking…", systemImage: "ellipsis", role: .muted) }
    switch status {
    case nil: return nil
    case .ok: return BoardStatus(word: "Connected", systemImage: "checkmark", role: .go)
    case .unauthorized, .unreachable, .other: return BoardStatus(word: "Not connected", systemImage: "exclamationmark.triangle", role: .danger)
    }
}

nonisolated func settingsHealthBadge(_ permission: HKPermission?) -> BoardStatus? {
    switch permission {
    case nil: nil
    case .granted: BoardStatus(word: "Connected", systemImage: "checkmark", role: .go)
    case .denied: BoardStatus(word: "Declined", systemImage: "exclamationmark.triangle", role: .danger)
    case .notDetermined: BoardStatus(word: "Not connected", systemImage: "minus", role: .muted)
    }
}

nonisolated func settingsDataQualityBadge(stale: Int?) -> BoardStatus? {
    guard let stale else { return nil }
    return stale == 0 ? BoardStatus(word: "All fresh", systemImage: "checkmark", role: .go)
        : BoardStatus(word: "\(stale) stale", systemImage: "exclamationmark.triangle", role: .danger)
}

public struct SettingsView: View {
    @Environment(\.jiTheme) private var theme
    private let model: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    public init(model: SettingsViewModel) { self.model = model }

    public var body: some View {
        NavigationStack {
            Form {
                ForEach(SettingsRootGroup.allCases, id: \.self) { group in
                    Section {
                        ForEach(SettingsRoot.rows.filter { $0.group == group }) { row in
                            rootRow(row)
                        }
                    } header: {
                        Text(group.title)
                    } footer: {
                        if group == .today {
                            Text(settingsTodayFooter).accessibilityIdentifier("settings.today.footer")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)   // W-GUI M5 (mockup 41): the grouped Form on the page ground
            .jiSoftTopEdge()   // W-FIX6 F6-15: soft fade under the bar, no hard (green-lit) band edge
            .jiPageGround()
            .environment(model)
            .navigationTitle("Settings")
            .toolbar {
                // W-FIX6 F6-15: a toolbar item — the bar draws its one glass, so Done sits inside
                // the bar instead of a 44 pt disc straddling the band's edge.
                ToolbarItem(placement: .confirmationAction) {
                    JIToolbarButton("checkmark", label: "Done") { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
            .task {
                // The Hub badge only says what a real test said: run one when a hub is set up.
                if model.connection.host != nil, model.connection.status == nil, !model.connection.testing {
                    await model.connection.test()
                }
            }
        }
        .jiTheme(.native)
    }

    private func sections(_ ids: [String]) -> [any SettingsSection] {
        ids.compactMap { id in model.sections.first { $0.id == id } }
    }

    @ViewBuilder
    private func rootRow(_ row: SettingsRootRow) -> some View {
        switch row.kind {
        case .inline:
            ForEach(sections(row.sectionIds), id: \.id) { section in
                AnyView(section.body)
                    .environment(\.settingsRowsOnly, true)
                    .accessibilityIdentifier("settings.section.\(section.id)")
            }
        case .push(let title, let systemImage, let placeholder):
            NavigationLink {
                SettingsSectionsScreen(title: title, sections: sections(row.sectionIds), placeholder: placeholder)
                    .environment(model)
            } label: {
                SettingsLinkLabel(title: title, subtitle: subtitle(for: row.id), systemImage: systemImage,
                                  badge: badge(for: row.id))
            }
            .accessibilityLabel(title)
            .accessibilityIdentifier("settings.root.\(row.id)")
        case .homeWidgets:
            NavigationLink {
                HomeWidgetsView().environment(model)
            } label: {
                SettingsLinkLabel(title: "Home & widgets", subtitle: homeWidgetsSubtitle(squares: model.kpiSelectedCount),
                                  systemImage: "square.grid.2x2")
            }
            .accessibilityLabel("Home & widgets")
            .accessibilityIdentifier("settings.root.\(row.id)")
        }
    }

    private func subtitle(for id: String) -> String? {
        switch id {
        case "hub": model.connection.host == nil ? "Not set up · backup, data quality, mirrors, export"
            : settingsSyncHubSubtitle(lastSync: model.lastSyncDate, now: Date())
        case "developer": "Data source switch (debug builds only)"
        default: nil
        }
    }

    private func badge(for id: String) -> BoardStatus? {
        switch id {
        case "hub": settingsHubBadge(model.connection.status, testing: model.connection.testing)
        case "health": settingsHealthBadge(model.healthPermissionModel?.permission)
        default: nil
        }
    }
}

// MARK: - W-FIX3 BUG-33 (AX3): nothing truncates, nothing collides

/// At accessibility text sizes a navigation title or subtitle that does not fit is cut ("Home &
/// widg…", "Everything that is not a daily…"); there the screen shows it as wrapping text at the
/// top of its list instead, and the bar keeps only the inline title.
public nonisolated func jiTitleWrapsInList(_ size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }

/// The Settings row icon column. `JIRow`'s fixed 28 pt holds a body-size symbol only up to the
/// default sizes; at AX3 the glyph is ~50 pt wide and ran into "Hub"/"Haptics". The column grows
/// with the body text size (≈1.4 × its point size), never below 28.
public nonisolated func settingsIconColumnWidth(_ size: DynamicTypeSize) -> CGFloat {
    let body: CGFloat = switch size {
    case .xSmall: 14
    case .small: 15
    case .medium: 16
    case .large: 17
    case .xLarge: 19
    case .xxLarge: 21
    case .xxxLarge: 23
    case .accessibility1: 28
    case .accessibility2: 33
    case .accessibility3: 40
    case .accessibility4: 47
    case .accessibility5: 53
    @unknown default: 17
    }
    return max(28, (body * 1.4).rounded(.up))
}

/// A pushed Settings screen: the given registry sections, as `GroupSettingsView` draws them.
struct SettingsSectionsScreen: View {
    let title: String
    let sections: [any SettingsSection]
    var placeholder: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Form {
            if jiTitleWrapsInList(typeSize) {
                Section {
                    Text(title)
                        .jiFont(.title, weight: .bold, tint: .text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                        .accessibilityIdentifier("settings.screen.title")
                }
            }
            // The four DATA rows share one card with their footer (as in `GroupSettingsView`).
            let split = settingsPartitionDataSections(sections.map(\.id))
            ForEach(sections.filter { split.standalone.contains($0.id) }, id: \.id) { section in
                AnyView(section.body)
                    .accessibilityIdentifier("settings.section.\(section.id)")
            }
            if !split.data.isEmpty {
                Section {
                    ForEach(split.data, id: \.self) { id in
                        if let section = sections.first(where: { $0.id == id }) {
                            AnyView(section.body)
                                .environment(\.settingsRowsOnly, true)
                                .accessibilityIdentifier("settings.section.\(section.id)")
                        }
                    }
                } header: {
                    Text(SettingsGroup.data.title)
                } footer: {
                    Text(settingsDataFooter).accessibilityIdentifier("settings.data.footer")
                }
            }
            if let placeholder {
                Section { Text(placeholder).jiFont(.body, tint: .muted) }
            }
        }
        .scrollContentBackground(.hidden)   // W-GUI M5: pushed settings screens on the page ground
        .jiSoftTopEdge()   // W-FIX6 F6-14
        .jiPageGround()
        .jiGlassBackButton()
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(jiTitleWrapsInList(typeSize) ? .inline : .automatic)
        #endif
        .toolbar {
            // AX: the wrapped title above is the heading; an inline copy would only be cut again.
            if jiTitleWrapsInList(typeSize) {
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            }
        }
        .jiTheme(.native)
    }
}

// MARK: - Built-in link rows (L0). Rows for screens that already exist (W3b KPIs, W4 goals-setup
// and backup). W5b screens (local mirrors, Health Connect, gate config) are NOT here — their
// lanes add their own sections.

/// RN row shape (bold title, muted subtitle, chevron) — B-33 §2b.2: the 44-pt `JIRow`. The
/// chevron comes from the enclosing `NavigationLink`, so the row never draws its own.
struct SettingsLinkLabel: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    /// B-57 W1: a row's state ("Locked", "Preparing…") sits trailing; the subtitle keeps saying
    /// what the row is for.
    var trailing: String? = nil
    /// B-57 W1 r4: a coloured status ("✓ Connected", "⚠ 2 stale", "1 of 3") in place of `trailing`.
    var badge: BoardStatus? = nil
    var tint: Color? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.jiTheme) private var theme
    var body: some View {
        if typeSize.isAccessibilitySize, badge != nil || trailing != nil {
            // AX sizes: the value drops under the title instead of squeezing it to a letter a line.
            VStack(alignment: .leading, spacing: 4) {
                row { EmptyView() }
                value
            }
        } else {
            row { value }
        }
    }

    /// W-FIX3 BUG-33: the icon sits in its own column sized for the text size
    /// (`settingsIconColumnWidth`), so at AX3 it no longer overlaps the title.
    @ViewBuilder private func row<T: View>(@ViewBuilder _ trailing: () -> T) -> some View {
        if let systemImage {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint ?? theme.color(.info))
                    .frame(width: settingsIconColumnWidth(typeSize))
                    .accessibilityHidden(true)
                JIRow(title: title, subtitle: subtitle, systemImage: nil, tint: tint, trailing: trailing)
            }
        } else {
            JIRow(title: title, subtitle: subtitle, systemImage: nil, tint: tint, trailing: trailing)
        }
    }

    @ViewBuilder private var value: some View {
        if let badge {
            if let symbol = badge.systemImage {
                BoardStatusLabel(word: badge.word, systemImage: symbol, role: badge.role)
            } else {
                Text(badge.word).jiFont(.subheadline, weight: .semibold, tint: badge.role)
            }
        } else if let trailing {
            Text(trailing).jiFont(.subheadline, tint: .muted)
        }
    }
}

/// W-TGT L3 (mock 04): the Preferences band's first row is Settings › Targets — Goals, Limits and
/// Rules on ONE screen over the phone's own document (no hub needed, so never "Connect to your
/// hub" while connected — F6-12). The square picker (My KPIs) moved to Home & widgets › On Today.
struct PreferencesLinksSection: SettingsSection {
    static let sectionId = "l0.preferences"
    let id = Self.sectionId
    let title = "Targets"
    let systemImage = "target"
    let sortKey = SettingsSortKey.preferences
    let group = SettingsGroupId.kpis
    var body: some View { PreferencesLinksRows() }
}

private struct PreferencesLinksRows: View {
    @Environment(SettingsViewModel.self) private var model
    /// The shell's model (edits mirror to the hub); without one, a local model over this Settings'
    /// prefs (previews, the sweep) — the numbers are the same stored document either way.
    @Environment(\.targetsModel) private var injected

    var body: some View {
        let targets = injected ?? TargetsModel(prefs: model.prefs)
        SettingsRowGroup(header: SettingsGroup.preferences.title) {
            NavigationLink { TargetsView(model: targets) } label: {
                SettingsLinkLabel(title: "Targets", subtitle: targetsSettingsSummary(targets.document), systemImage: "target")
            }
            .accessibilityLabel("Targets")
            .accessibilityIdentifier("settings.row.targets")
        }
    }
}

/// RN "Data": Backup & restore → `BackupView` (W4-L4). Local mirrors / Health Connect are W5b.
struct DataLinksSection: SettingsSection {
    static let sectionId = "l0.data"
    let id = Self.sectionId
    let title = SettingsGroup.data.title
    let systemImage = "externaldrive"
    let sortKey = SettingsSortKey.data
    let group = SettingsGroupId.sync
    var body: some View { DataLinksRows() }
}

private struct DataLinksRows: View {
    @Environment(SettingsViewModel.self) private var model
    var body: some View {
        SettingsRowGroup(header: SettingsGroup.data.title) {
            if let backup = model.backupModel {
                NavigationLink { BackupView(model: backup) } label: {
                    SettingsLinkLabel(title: "Backup & restore", subtitle: settingsDataSubtitles["Backup & restore"] ?? "",
                                      systemImage: "archivebox",
                                      trailing: backup.lastBackupAt?.formatted(.dateTime.day().month(.abbreviated)))
                }
                .accessibilityLabel("Backup & restore")
                .accessibilityIdentifier("settings.row.backup")
            } else {
                // Rule 5: never a silently missing row — the vault unlocks on the Journal tab.
                SettingsLinkLabel(title: "Backup & restore", subtitle: settingsDataSubtitles["Backup & restore"] ?? "",
                                  systemImage: "archivebox", trailing: "Locked")
                    .accessibilityHint("Open the Journal tab once to unlock the vault first")
                    .accessibilityIdentifier("settings.row.backup.unavailable")
            }
        }
    }
}
