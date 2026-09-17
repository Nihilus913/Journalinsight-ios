import Foundation
import Observation
import JIPersistence

// W5a-L4 (P-version). Mirrors `mobile/app/version.tsx` (identity card + changelog) and
// `mobile/src/data/versionSeen.ts` (`recordVersionSeen` / `useHasNewVersion`), persisted through
// `PrefStore` instead of SecureStore — it is a non-credential marker and `PrefStore` is the one
// on-device store every W5a screen uses.

/// App identity as the screen shows it. `init(bundle:)` reads `Bundle.main`'s Info.plist keys;
/// tests inject values directly.
public nonisolated struct VersionInfo: Sendable, Equatable {
    public let appName: String
    /// `CFBundleShortVersionString` (marketing version).
    public let appVersion: String
    /// `CFBundleVersion` (build number).
    public let build: String
    public let bundleId: String

    public init(appName: String, appVersion: String, build: String, bundleId: String) {
        self.appName = appName; self.appVersion = appVersion; self.build = build; self.bundleId = bundleId
    }

    /// Rule 5 in spirit: never a blank identity — every missing key falls back to something true.
    public init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary ?? [:]
        let display = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
        appName = display?.isEmpty == false ? display! : Changelog.appName
        appVersion = (info["CFBundleShortVersionString"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "0"
        build = (info["CFBundleVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "0"
        bundleId = bundle.bundleIdentifier ?? "toby913.JournalInsight"
    }
}

@Observable @MainActor
public final class VersionViewModel {
    public let info: VersionInfo
    public let entries: [ChangelogEntry]
    /// True once `markSeen()` has recorded THIS build (or a previous launch did).
    public private(set) var hasBeenSeen: Bool

    private let prefs: PrefStore

    public init(prefs: PrefStore, info: VersionInfo = VersionInfo(), entries: [ChangelogEntry] = Changelog.entries) {
        self.prefs = prefs
        self.info = info
        self.entries = entries
        self.hasBeenSeen = !Self.hasNewVersion(prefs: prefs, appVersion: info.appVersion)
    }

    public var appName: String { info.appName }
    public var bundleId: String { info.bundleId }
    /// RN shows "Version {APP_VERSION}"; iOS adds the build number in parentheses.
    public var versionLine: String { "Version \(info.appVersion) (\(info.build))" }

    /// RN `recordVersionSeen(APP_VERSION)` — called when the screen appears; this is what clears
    /// the what's-new dot (`hasNewVersion`) on the Settings gear.
    public func markSeen() {
        try? prefs.set(Changelog.seenPrefKey, info.appVersion)
        hasBeenSeen = true
    }

    /// RN `useHasNewVersion`: true when no marker was ever recorded or it differs from this build.
    public nonisolated static func hasNewVersion(prefs: PrefStore, appVersion: String) -> Bool {
        let seen = (try? prefs.get(Changelog.seenPrefKey, as: String.self)) ?? nil
        return seen != appVersion
    }
}
