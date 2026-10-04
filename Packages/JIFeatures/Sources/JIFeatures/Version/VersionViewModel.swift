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

    /// B-18 p2: on-device crash records (newest first, at most `CrashLogStore.cap`). Local only.
    public private(set) var crashes: [CrashRecord]
    /// Set when Clear fails (rule 5: say so, never pretend it worked).
    public private(set) var crashClearError: String?

    private let prefs: PrefStore
    private let crashStore: CrashLogStore?

    public init(prefs: PrefStore, info: VersionInfo = VersionInfo(), entries: [ChangelogEntry] = Changelog.entries,
                crashStore: CrashLogStore? = .default) {
        self.prefs = prefs
        self.info = info
        self.entries = entries
        self.crashStore = crashStore
        self.crashes = crashStore?.list() ?? []
        self.hasBeenSeen = !Self.hasNewVersion(prefs: prefs, appVersion: info.appVersion)
    }

    /// The record the "Last crash" section shows; nil = "No crashes recorded".
    public var lastCrash: CrashRecord? { crashes.first }

    /// Re-reads the store (the screen calls this on appear: MetricKit may have delivered since).
    public func reloadCrashes() {
        crashes = crashStore?.list() ?? []
    }

    /// Deletes every stored record and refreshes the list.
    public func clearCrashes() {
        guard let crashStore else { crashes = []; return }
        do {
            try crashStore.clear()
            crashClearError = nil
        } catch {
            crashClearError = "Could not clear crash logs: \(error.localizedDescription)"
        }
        crashes = crashStore.list()
    }

    /// "4 Oct 2026, 21:08" in the given time zone (tests pin UTC).
    public nonisolated static func crashDateLine(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = timeZone
        f.dateFormat = "d MMM yyyy, HH:mm"
        return f.string(from: date)
    }

    /// "2.0.0 · build 42" for the crashed build (may differ from the running one).
    public nonisolated static func crashBuildLine(_ r: CrashRecord) -> String { "\(r.appVersion) · build \(r.build)" }

    /// "Uncaught exception" / "MetricKit".
    public nonisolated static func crashSourceLine(_ r: CrashRecord) -> String {
        r.source == .exception ? "Uncaught exception" : "MetricKit"
    }

    /// Copy/Share text: the latest record's report, plus older ones separated by a rule.
    public var crashReportText: String {
        crashes.map(\.reportText).joined(separator: "\n\n---\n\n")
    }

    public var appName: String { info.appName }
    public var bundleId: String { info.bundleId }
    /// RN shows "Version {APP_VERSION}"; iOS adds the build number in parentheses.
    public var versionLine: String { "Version \(info.appVersion) (\(info.build))" }
    /// B-57 W1 board: "2.0.0 · build 42".
    public var shortVersionLine: String { "\(info.appVersion) · build \(info.build)" }

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
