import SwiftUI
import JIDesign

// W5a-L4 (P-version). Mirrors `mobile/app/version.tsx`: identity card (icon, name, version,
// bundle id), then "What changed" — one card per `ChangelogEntry` with its bullet items.
// RN's "Last crash" section (Android-only Kotlin module there) is B-18 p2 on iOS: the newest on-device
// `CrashRecord` (uncaught NSException / MetricKit, see CrashLog.swift) with Copy / Share / Clear;
// local only, never uploaded. No Done button: this view
// is pushed inside `SettingsView`'s `NavigationStack`, whose toolbar already carries Done.
/// B-57 W1 r4 (fixer g3, board 5/05): the identity sits in one compact row, "What changed" is the
/// three latest releases (each opens its notes one level down, plus "All releases" for the full
/// changelog), and "This install" says where this phone's numbers come from (hub · data quality).
public nonisolated struct VersionInstallState: Sendable, Equatable {
    /// The Settings Hub row's subtitle ("192.168.1.5 · last sync 07:41" / "Not set up").
    public let hub: String
    public let hubConnected: Bool
    public init(hub: String, hubConnected: Bool) { self.hub = hub; self.hubConnected = hubConnected }
}

/// The latest releases the board lists, newest first; `installed` marks this build's own entry.
public nonisolated struct VersionHighlight: Sendable, Equatable, Identifiable {
    public let entry: ChangelogEntry
    public let installed: Bool
    public var id: String { entry.id }
}

public nonisolated func versionHighlights(_ entries: [ChangelogEntry], appVersion: String, limit: Int = 3) -> [VersionHighlight] {
    entries.prefix(limit).map { VersionHighlight(entry: $0, installed: $0.version == appVersion) }
}

/// "2026-09-17" → "17 Sep"; anything else is shown as-is (never a guessed date).
public nonisolated func versionShortDate(_ iso: String) -> String {
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, (1...12).contains(parts[1]) else { return iso }
    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return "\(parts[2]) \(months[parts[1] - 1])"
}

/// Board footnote under "What changed".
public nonisolated let versionReferenceNote = "\(Changelog.rnAppVersion) is the last React Native build, kept as the reference."

public struct VersionView: View {
    @Environment(\.jiTheme) private var theme
    @State private var model: VersionViewModel
    private let thisInstall: VersionInstallState?
    @State private var staleSources: Int?
    @State private var confirmClearCrashes = false
    @State private var copiedCrash = false

    public init(model: VersionViewModel, thisInstall: VersionInstallState? = nil) {
        _model = State(initialValue: model)
        self.thisInstall = thisInstall
    }

    public var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AppIconImage()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.nested), style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.appName).jiFont(.cardTitle, weight: .bold, tint: .text)
                        Text(model.shortVersionLine).jiFont(.subheadline, weight: .semibold, tint: .text)
                            .accessibilityIdentifier("version.line")
                        Text(versionPlatformLine).jiFont(.footnote, tint: .muted)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("version.identity")
            }

            Section {
                ForEach(versionHighlights(model.entries, appVersion: model.info.appVersion)) { row in
                    NavigationLink { ReleaseNotesScreen(entries: [row.entry], title: row.entry.version) } label: {
                        SettingsLinkLabel(title: "\(row.entry.version) \(row.entry.title)",
                                          subtitle: row.installed ? versionShortDate(row.entry.date) : nil,
                                          trailing: row.installed ? nil : versionShortDate(row.entry.date),
                                          badge: row.installed ? BoardStatus(word: "Installed", systemImage: "checkmark", role: .go) : nil)
                    }
                    .accessibilityIdentifier("version.entry.\(row.entry.id)")
                }
                NavigationLink { ReleaseNotesScreen(entries: model.entries, title: "All releases") } label: {
                    JIRow(title: "All releases") { Text("\(model.entries.count)").jiFont(.subheadline, tint: .muted) }
                }
                .accessibilityIdentifier("version.allReleases")
            } header: {
                Text("What changed")
            } footer: {
                Text(versionReferenceNote)
            }

            Section("This install") {
                JIRow(title: "Hub") {
                    Text(thisInstall?.hub ?? "—").jiFont(.subheadline, tint: thisInstall?.hubConnected == true ? .text : .muted)
                        .lineLimit(2).multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("version.install.hub")
                NavigationLink {
                    DataQualityScreen()   // F-5: owns its model across re-renders
                } label: {
                    SettingsLinkLabel(title: "Data quality", trailing: "—", badge: settingsDataQualityBadge(stale: staleSources))
                }
                .accessibilityIdentifier("version.install.dataQuality")
            }

            crashSection
        }
        .jiNativeFormChrome()
        .scrollContentBackground(.hidden)   // W-GUI tier B: on the page ground
        .jiPageGround()
        .jiGlassBackButton()
        .readableColumn()
        .jiTheme(.native)
        .navigationTitle("About & version")
        .onAppear { model.markSeen(); model.reloadCrashes() }
        .confirmationDialog("Clear all crash logs?", isPresented: $confirmClearCrashes, titleVisibility: .visible) {
            Button("Clear crash logs", role: .destructive) { model.clearCrashes() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the \(model.crashes.count) stored report\(model.crashes.count == 1 ? "" : "s") from this phone.")
        }
        .task {
            guard staleSources == nil, let dq = DataQualityAccess.shared.makeViewModel() else { return }
            await dq.load()
            if dq.phase == .loaded, !dq.sourceSummary.sources.isEmpty { staleSources = dq.sourceSummary.stale }
        }
    }

    /// B-18 p2: "Last crash" — empty state, or date / build / type / summary + Copy · Share · Clear.
    @ViewBuilder private var crashSection: some View {
        Section {
            if let crash = model.lastCrash {
                VStack(alignment: .leading, spacing: 4) {
                    Text(crash.type).jiFont(.subheadline, weight: .bold, tint: .text)
                        .accessibilityIdentifier("version.crash.type")
                    Text(crash.summary).jiFont(.footnote, tint: .text).lineLimit(4)
                        .accessibilityIdentifier("version.crash.summary")
                    Text("\(VersionViewModel.crashDateLine(crash.date)) · \(VersionViewModel.crashBuildLine(crash)) · \(VersionViewModel.crashSourceLine(crash))")
                        .jiFont(.caption, tint: .muted)
                        .accessibilityIdentifier("version.crash.meta")
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("version.crash.latest")

                Button {
                    copyCrashReport()
                } label: {
                    Label(copiedCrash ? "Copied" : "Copy report", systemImage: copiedCrash ? "checkmark" : "doc.on.doc")
                }
                .accessibilityIdentifier("version.crash.copy")

                ShareLink(item: model.crashReportText,
                          preview: SharePreview("JournalInsight crash report")) {
                    Label("Share report", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("version.crash.share")

                Button(role: .destructive) {
                    confirmClearCrashes = true
                } label: {
                    Label("Clear crash logs", systemImage: "trash")
                }
                .accessibilityIdentifier("version.crash.clear")
            } else {
                Text("No crashes recorded").jiFont(.subheadline, tint: .muted)
                    .accessibilityIdentifier("version.crash.empty")
            }
        } header: {
            Text("Last crash")
        } footer: {
            if let err = model.crashClearError {
                Text(err).accessibilityIdentifier("version.crash.error")
            } else if model.crashes.count > 1 {
                Text("\(model.crashes.count) reports stored on this phone (newest \(CrashLogStore.cap) kept). Copy and Share include all of them.")
            } else {
                Text("Stored on this phone only — never sent to the hub.")
            }
        }
    }

    private func copyCrashReport() {
        #if canImport(UIKit)
        UIPasteboard.general.string = model.crashReportText
        #endif
        copiedCrash = true
    }

    private var versionPlatformLine: String {
        #if os(iOS)
        "iOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion) · Swift native"
        #else
        "Swift native"
        #endif
    }
}

/// One level down: the release notes the main screen used to print in full.
struct ReleaseNotesScreen: View {
    let entries: [ChangelogEntry]
    let title: String
    var body: some View {
        List {
            ForEach(entries) { entry in
                Section { ChangelogEntryRow(entry: entry).accessibilityIdentifier("version.notes.\(entry.id)") }
            }
        }
        .jiNativeFormChrome()
        .scrollContentBackground(.hidden)   // W-GUI tier B: on the page ground
        .jiPageGround()
        .jiGlassBackButton()
        .readableColumn()
        .jiTheme(.native)
        .navigationTitle(title)
    }
}

/// One release card: "1.2.3 — Title", muted date, accent bullets.
struct ChangelogEntryRow: View {
    @Environment(\.jiTheme) private var theme
    let entry: ChangelogEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(entry.version) — \(entry.title)").jiFont(.subheadline, weight: .bold).foregroundStyle(theme.color(.text))
            Text(entry.date).jiFont(.micro).foregroundStyle(theme.color(.muted))
            ForEach(Array(entry.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").jiFont(.caption).foregroundStyle(theme.color(.info))
                    Text(item).jiFont(.caption).foregroundStyle(theme.color(.muted))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// The bundle's primary app icon when the platform exposes it, else a neutral placeholder
/// (never blank — rule 5).
private struct AppIconImage: View {
    @Environment(\.jiTheme) private var theme
    var body: some View {
        #if canImport(UIKit)
        if let ui = UIImage(named: "AppIcon") ?? primaryIcon() {
            Image(uiImage: ui).resizable()
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: theme.radius(.nested), style: .continuous)
            .fill(theme.color(.surface2))
            .overlay(Image(systemName: "book.closed.fill").font(.title).foregroundStyle(theme.color(.info)))
    }

    #if canImport(UIKit)
    private func primaryIcon() -> UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let last = files.last else { return nil }
        return UIImage(named: last)
    }
    #endif
}
