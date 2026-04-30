//
//  JournalInsightApp.swift
//  JournalInsight
//

import SwiftUI
import SwiftData

@main
struct JournalInsightApp: App {
    @AppStorage(StorageKeys.selectedAppearance) private var selectedAppearance: AppAppearance = .system
    @AppStorage(StorageKeys.textSize) private var textSize: TextSizeChoice = .medium
    @AppStorage(StorageKeys.accentColor) private var accentColorChoice: AccentColorChoice = .teal

    @State private var lockPolicy = LockPolicySettings()
    @State private var bootCoordinator: BootCoordinator?
    @State private var migrationSheetState: MigrationSheet.State = .idle
    @State private var vault: VaultManager?
    @State private var syncObserver = SyncStatusObserver()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let coord = bootCoordinator {
                    rootContent(for: coord)
                } else {
                    Color(.systemBackground).ignoresSafeArea()
                        .task { await initBoot() }
                }
            }
            .preferredColorScheme(colorScheme)
            .dynamicTypeSize(textSize.sizeCategory)
            .tint(accentColorChoice.color)
            .privacyOverlay()
            .onChange(of: scenePhase) { _, newPhase in
                Task { await vault?.handleScenePhaseChange(newPhase) }
            }
        }
    }

    @ViewBuilder
    private func rootContent(for coord: BootCoordinator) -> some View {
        switch coord.state {
        case .starting, .awaitingMigration, .migrating, .migrationFailed:
            MigrationSheet(
                state: $migrationSheetState,
                onContinue: {
                    Task {
                        migrationSheetState = .encrypting(current: 0, total: 0)
                        await coord.runMigration()
                        syncSheetStateFromCoordinator(coord)
                    }
                },
                onRetry: {
                    Task {
                        migrationSheetState = .encrypting(current: 0, total: 0)
                        await coord.runMigration()
                        syncSheetStateFromCoordinator(coord)
                    }
                }
            )
            .task(id: coord.state) {
                syncSheetStateFromCoordinator(coord)
            }
        case .ready(let container):
            // `vault` is non-nil by construction here (initBoot assigns it before
            // building the BootCoordinator that produces .ready), but prefer an
            // explicit if-let to avoid a force-unwrap in the hot view body.
            if let vault {
                MainScreenView()
                    .modelContainer(container)
                    .environment(lockPolicy)
                    .environment(\.vault, vault)
                    .environment(syncObserver)
            }
        }
    }

    private func syncSheetStateFromCoordinator(_ coord: BootCoordinator) {
        switch coord.state {
        case .starting:
            migrationSheetState = .idle
        case .awaitingMigration:
            migrationSheetState = .idle
        case .migrating(let current, let total):
            migrationSheetState = .encrypting(current: current, total: total)
        case .migrationFailed(let message):
            migrationSheetState = .failed(message: message)
        case .ready:
            migrationSheetState = .done
        }
    }

    private func initBoot() async {
        let v = VaultManager(keychain: KeychainStore(), lockPolicy: lockPolicy)
        self.vault = v
        let coord = BootCoordinator(vault: v)
        self.bootCoordinator = coord
        await coord.startBoot()
        syncSheetStateFromCoordinator(coord)
    }

    private var colorScheme: ColorScheme? {
        switch selectedAppearance {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }
}

// VaultManager is an `actor` and therefore cannot satisfy SwiftUI's
// `@Environment(_:)` Observable-environment requirement. We expose it via a
// keyed EnvironmentValues entry instead. Plan 5 will consume this via
// `@Environment(\.vault)` to drive the lock UI.
private struct VaultManagerKey: EnvironmentKey {
    static let defaultValue: VaultManager? = nil
}

extension EnvironmentValues {
    var vault: VaultManager? {
        get { self[VaultManagerKey.self] }
        set { self[VaultManagerKey.self] = newValue }
    }
}
