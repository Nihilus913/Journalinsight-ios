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

// B-57 W1 r4 (fixer g3, board 5/01 decided from the PNG): CONNECTION = Hub · Apple Health ·
// Sync now (the real sync action) · PREFERENCES = Goals · My KPIs · Appearance · Reminders ·
// Home & widgets · Haptics (a toggle, not a push) · DATA = the four rows + footer · ADVANCED =
// About & version, plus the two destinations the board has no row for, so they stay reachable:
// Gate config and Haptic strength (the intensity slider + "Feel it").

/// One row (or run of inline rows) on the Settings root.
public nonisolated struct SettingsRootRow: Sendable, Identifiable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The sections' own link rows, drawn straight into the group's card.
        case inline
        /// One row that pushes a screen holding these sections.
        case push(title: String, systemImage: String, placeholder: String?)
        /// The board's "Sync now" action row (shown only when the app passed a sync action).
        case syncNow
        /// The board's Haptics on/off switch, inline.
        case hapticsToggle
    }
    public let id: String
    public let group: SettingsGroup
    public let kind: Kind
    public let sectionIds: [String]
}

public nonisolated enum SettingsRoot {
    public static let rows: [SettingsRootRow] = {
        var rows: [SettingsRootRow] = [
            .init(id: "hub", group: .connection, kind: .push(title: "Hub", systemImage: "server.rack", placeholder: nil),
                  sectionIds: ["l0.hub"]),
            .init(id: "health", group: .connection, kind: .push(title: "Apple Health", systemImage: "heart", placeholder: nil),
                  sectionIds: ["l0.health"]),
            .init(id: "syncNow", group: .connection, kind: .syncNow, sectionIds: []),
            .init(id: "preferences", group: .preferences, kind: .inline,
                  sectionIds: ["l0.preferences", "l1.appearance", "l2.reminders"]),
            .init(id: "home", group: .preferences,
                  kind: .push(title: "Home & widgets", systemImage: "square.grid.2x2",
                              placeholder: SettingsGroupId.widgets.placeholder),
                  sectionIds: ["l3.editToday", "l5.weeklyPlan"]),
            .init(id: "haptics", group: .preferences, kind: .hapticsToggle, sectionIds: []),
            .init(id: "data", group: .data, kind: .inline, sectionIds: settingsDataSectionIds),
            .init(id: "about", group: .advanced, kind: .inline, sectionIds: ["l4.version", "w5b.gateConfig"]),
            .init(id: "hapticStrength", group: .advanced,
                  kind: .push(title: "Haptic strength", systemImage: "iphone.radiowaves.left.and.right", placeholder: nil),
                  sectionIds: ["w8.haptics"]),
        ]
        #if DEBUG
        rows.append(.init(id: "developer", group: .advanced,
                          kind: .push(title: "Developer", systemImage: "hammer", placeholder: nil),
                          sectionIds: ["l3.provider"]))
        #endif
        return rows
    }()

    /// The board's four headers, in order.
    public static var headers: [String] { SettingsGroup.allCases.map(\.title) }
}

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

/// Reminders row: how many daily + workout reminders are switched on ("Off" when none).
public nonisolated func settingsRemindersTrailing(_ prefs: RemindersPrefs?) -> String {
    let on = (prefs?.daily.values.filter(\.enabled).count ?? 0) + (prefs?.workouts.values.filter(\.enabled).count ?? 0)
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
    if failed { return "Failed" }
    guard let lastSync else { return "—" }
    return settingsClock(lastSync, now: now, calendar: calendar)
}

public nonisolated func settingsHubSubtitle(host: String?, lastSync: Date?, now: Date,
                                            calendar: Calendar = .autoupdatingCurrent) -> String {
    guard let host, !host.isEmpty else { return "Not set up" }
    guard let lastSync else { return host }
    return "\(host) · last sync \(settingsClock(lastSync, now: now, calendar: calendar))"
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
    @State private var haptics: HapticsViewModel?

    public init(model: SettingsViewModel) { self.model = model }

    public var body: some View {
        NavigationStack {
            Form {
                ForEach(SettingsGroup.allCases, id: \.self) { group in
                    Section {
                        ForEach(SettingsRoot.rows.filter { $0.group == group }) { row in
                            rootRow(row)
                        }
                    } header: {
                        Text(group.title)
                    } footer: {
                        if group == .data {
                            Text(settingsDataFooter).accessibilityIdentifier("settings.data.footer")
                        }
                    }
                }
            }
            .environment(model)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(theme.color(.info))
                        .accessibilityLabel("Done")
                        .accessibilityIdentifier("settings.done")
                }
            }
            .task {
                if haptics == nil { haptics = HapticsViewModel(prefs: model.prefs) }
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
        case .syncNow:
            if model.canSyncNow {
                Button { Task { await model.syncNow() } } label: {
                    SettingsLinkLabel(title: "Sync now", systemImage: "arrow.triangle.2.circlepath",
                                      trailing: settingsSyncTrailing(syncing: model.syncing, failed: model.syncFailed,
                                                                     lastSync: model.lastSyncDate, now: Date()))
                }
                .buttonStyle(.plain)
                .disabled(model.syncing)
                .accessibilityLabel("Sync now")
                .accessibilityHint("Sends Apple Health to the hub, then asks the hub to sync Garmin and YAZIO")
                .accessibilityIdentifier("settings.root.syncNow")
            }
        case .hapticsToggle:
            if let haptics {
                Toggle(isOn: Binding(get: { haptics.enabled }, set: { haptics.setEnabled($0) })) {
                    SettingsLinkLabel(title: "Haptics", systemImage: "iphone.radiowaves.left.and.right")
                }
                .tint(theme.color(.info))
                .onAppear { haptics.refresh() }
                .accessibilityLabel(haptics.enabled ? "Haptics On" : "Haptics Off")
                .accessibilityIdentifier("settings.root.haptics")
            } else {
                SettingsLinkLabel(title: "Haptics", systemImage: "iphone.radiowaves.left.and.right")
            }
        }
    }

    private func subtitle(for id: String) -> String? {
        switch id {
        case "hub": settingsHubSubtitle(host: model.connection.host, lastSync: model.lastSyncDate, now: Date())
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
            ForEach(sections, id: \.id) { section in
                AnyView(section.body)
                    .accessibilityIdentifier("settings.section.\(section.id)")
            }
            if let placeholder {
                Section { Text(placeholder).jiFont(.body, tint: .muted) }
            }
        }
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

/// RN "Preferences": Goals → `GoalsSetupView` (W4-L3), My KPIs → `KpiListView` (W3b-L2).
/// Edit Today (L3) and Appearance (L1) register their own sections in this band.
struct PreferencesLinksSection: SettingsSection {
    static let sectionId = "l0.preferences"
    let id = Self.sectionId
    let title = SettingsGroup.preferences.title
    let systemImage = "slider.horizontal.3"
    let sortKey = SettingsSortKey.preferences
    let group = SettingsGroupId.kpis
    var body: some View { PreferencesLinksRows() }
}

private struct PreferencesLinksRows: View {
    @Environment(SettingsViewModel.self) private var model
    var body: some View {
        SettingsRowGroup(header: SettingsGroup.preferences.title) {
            if let goals = model.goalsSetupModel {
                NavigationLink { GoalsSetupView(model: goals) } label: {
                    SettingsLinkLabel(title: "Goals", systemImage: "target", trailing: settingsGoalsTrailing(goals.goals))
                }
                .task { if goals.goals == nil { await goals.load() } }
                .accessibilityLabel("Goals")
                .accessibilityIdentifier("settings.row.goals")
            } else {
                SettingsLinkLabel(title: "Goals", subtitle: "Connect to your hub to edit goals", systemImage: "target")
                    .accessibilityIdentifier("settings.row.goals.unavailable")
            }
            if let kpis = model.kpiListModel {
                NavigationLink { KpiListView(model: kpis) } label: {
                    SettingsLinkLabel(title: "My KPIs", systemImage: "chart.bar",
                                      trailing: settingsKpisTrailing(model.kpiSelectedCount))
                }
                .accessibilityLabel("My KPIs")
                .accessibilityIdentifier("settings.row.kpis")
            } else {
                SettingsLinkLabel(title: "My KPIs", subtitle: "Connect to your hub to choose KPIs", systemImage: "chart.bar")
                    .accessibilityIdentifier("settings.row.kpis.unavailable")
            }
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
