import Foundation
import SwiftUI
import JIDesign
import JIFeatures

/// RG-02 / B-118: how launch went for local storage. `.storageFull` = the on-disk SQLite stores
/// (cache + prefs) could not be opened — typically a full disk — and the app runs in hub-only read
/// mode on an in-memory environment instead of trapping.
enum AppStorageState: Equatable {
    case ready
    case storageFull(reason: String)
}

/// Builds the launch `AppEnvironment`. Replaces the old `fatalError("AppEnvironment init failed…")`
/// in `JournalInsightApp.init()`: an open failure is recorded in the CrashLog (Version → Last crash)
/// and the app falls back to an in-memory environment. `env == nil` only when even the in-memory
/// open fails; the app then shows the Storage-full screen alone.
@MainActor
enum AppEnvironmentBootstrap {
    struct Result {
        let env: AppEnvironment?
        let state: AppStorageState
    }

    /// `-JIForceStorageFull YES` (UserDefaults argument domain) simulates the open failure, for
    /// the simulator proof of the Storage-full screen.
    nonisolated static func forceStorageFullRequested(_ arguments: [String] = CommandLine.arguments) -> Bool {
        guard let i = arguments.firstIndex(of: "-JIForceStorageFull"), arguments.index(after: i) < arguments.endIndex else { return false }
        return ["yes", "true", "1"].contains(arguments[arguments.index(after: i)].lowercased())
    }

    struct SimulatedStorageFull: Error, CustomStringConvertible {
        var description: String { "Simulated (-JIForceStorageFull): database or disk is full" }
    }

    static func make(
        forceStorageFull: Bool = forceStorageFullRequested(),
        onDisk: () throws -> AppEnvironment = { try AppEnvironment() },
        inMemory: () throws -> AppEnvironment = { try AppEnvironment(inMemory: true) },
        crashStore: CrashLogStore = .default,
        info: VersionInfo = VersionInfo(),
        now: Date = Date()
    ) -> Result {
        do {
            if forceStorageFull { throw SimulatedStorageFull() }
            return Result(env: try onDisk(), state: .ready)
        } catch {
            let reason = String(describing: error)
            // Best effort: on a really full disk this write can fail too — never fatal.
            try? crashStore.write(CrashRecord(date: now, source: .exception, appVersion: info.appVersion,
                                              build: info.build, type: "StorageFull",
                                              summary: "Local storage could not be opened at launch: \(reason)"))
            return Result(env: try? inMemory(), state: .storageFull(reason: reason))
        }
    }
}

/// The screen shown instead of a crash when local storage cannot be opened.
struct StorageFullView: View {
    let reason: String
    /// nil = no in-memory environment either; the screen is all the app can show.
    let onContinue: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Storage is full")
                .font(.title.bold())
                .accessibilityIdentifier("storageFull.title")
            Text("JournalInsight could not open its local database. Free up space on this iPhone, then reopen the app.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let onContinue {
                Text("Until then the app can read from the hub only: nothing you enter is saved on this phone.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Continue read-only", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0x38 / 255, green: 0xbd / 255, blue: 0xf8 / 255))
                    .accessibilityIdentifier("storageFull.continue")
            }
            Text(reason)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("storageFull.reason")
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
