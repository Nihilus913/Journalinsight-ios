import SwiftUI
import JIDesign

// W5a-L4 (P-version). Mirrors `mobile/app/version.tsx`: identity card (icon, name, version,
// bundle id), then "What changed" — one card per `ChangelogEntry` with its bullet items.
// RN's "Last crash" section is descoped (Android-only Kotlin module). No Done button: this view
// is pushed inside `SettingsView`'s `NavigationStack`, whose toolbar already carries Done.
public struct VersionView: View {
    @Environment(\.jiTheme) private var theme
    @State private var model: VersionViewModel

    public init(model: VersionViewModel) { _model = State(initialValue: model) }

    public var body: some View {
        List {
            Section {
                VStack(spacing: 4) {
                    AppIconImage()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.nested), style: .continuous))
                        .padding(.bottom, 6)
                        .accessibilityLabel("App icon")
                    Text(model.appName).jiFont(.title, weight: .heavy).foregroundStyle(theme.color(.text))
                    Text(model.versionLine).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("version.line")
                    Text(model.bundleId).jiFont(.micro).foregroundStyle(theme.color(.muted))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("version.identity")
            }
            Section("What changed") {
                ForEach(model.entries) { entry in
                    ChangelogEntryRow(entry: entry)
                        .accessibilityIdentifier("version.entry.\(entry.id)")
                }
            }
        }
        .jiNativeFormChrome()
        .jiTheme(.native)
        .navigationTitle("About & version")
        .onAppear { model.markSeen() }
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
