// JournalInsight/Migration/BootCoordinator.swift
import Foundation
import SwiftData
import os

@MainActor
@Observable
final class BootCoordinator {

    enum BootState: Equatable {
        case starting                              // pre-Stage-1
        case awaitingMigration                     // pending > 0, sheet should show .idle
        case migrating(current: Int, total: Int)
        case migrationFailed(message: String)
        case ready(ModelContainer)
    }

    private(set) var state: BootState = .starting

    private let storeURL: URL
    private let cloudKitContainerID: String
    private let vault: VaultManager

    init(
        storeURL: URL = URL.applicationSupportDirectory.appendingPathComponent("default.store"),
        cloudKitContainerID: String = "iCloud.com.tobias.JournalInsight",
        vault: VaultManager
    ) {
        self.storeURL = storeURL
        self.cloudKitContainerID = cloudKitContainerID
        self.vault = vault
    }

    /// Step 1: build the pre-migration container (CloudKit off) and check pending.
    /// Returns the pre-migration ModelContainer so the caller can present the sheet
    /// against it if migration is needed.
    func startBoot() async {
        do {
            // Set .complete file protection on the parent directory before opening
            try ensureFileProtection()
            let pre = try buildContainer(cloudKit: false)
            let preCtx = ModelContext(pre)
            let pending = try MigrationCoordinator.pendingCount(in: preCtx)
            if pending == 0 {
                // Empty DB or already migrated — go straight to final container.
                let final = try buildContainer(cloudKit: true)
                state = .ready(final)
            } else {
                state = .awaitingMigration
                // Sheet drives the actual run via runMigration(in:)
                self.cachedPreContainer = pre
            }
        } catch {
            Logger.migration.error("boot failed: \(error.localizedDescription, privacy: .public)")
            state = .migrationFailed(message: error.localizedDescription)
        }
    }

    /// Step 2: invoked when user taps Continue on the migration sheet.
    func runMigration() async {
        guard let pre = cachedPreContainer else {
            state = .migrationFailed(message: "Boot did not produce a pre-migration container.")
            return
        }
        let ctx = ModelContext(pre)
        do {
            try await MigrationCoordinator.run(in: ctx, vault: vault) { [weak self] current, total in
                self?.state = .migrating(current: current, total: total)
            }
            // Build the final container BEFORE dropping the pre-container reference.
            // If the CloudKit-enabled open throws (e.g. iCloud signed out, network glitch),
            // we keep the cached pre-container so Retry can re-attempt without bricking
            // the user. cachedPreContainer is nilled only after final build succeeds.
            let final = try buildContainer(cloudKit: true)
            cachedPreContainer = nil
            state = .ready(final)
        } catch {
            Logger.migration.error("migration failed: \(error.localizedDescription, privacy: .public)")
            state = .migrationFailed(message: error.localizedDescription)
        }
    }

    private var cachedPreContainer: ModelContainer?

    private func buildContainer(cloudKit: Bool) throws -> ModelContainer {
        let schema = Schema([JournalEntry.self, Goal.self, Tag.self])
        let cfg: ModelConfiguration
        if cloudKit {
            cfg = ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
        } else {
            cfg = ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
        }
        // We rely on SwiftData's automatic lightweight migration for the V0→V1
        // shape change (additive columns with defaults, dropped Tag uniqueness,
        // widened text/moodRaw nullability). An explicit `migrationPlan:` was
        // attempted but SwiftData crashes when V0 and V1 reference identical
        // model types at the Swift type level — see ContainerSwapTests, which
        // surfaced this as the release-blocker design flaw. Per-row schema
        // version is tracked via `JournalEntry.schemaVersion` and gated by
        // MigrationCoordinator.pendingCount; SchemaVersions.swift remains as
        // documentation of intent.
        return try ModelContainer(for: schema, configurations: cfg)
    }

    private func ensureFileProtection() throws {
        let fm = FileManager.default
        let parent = storeURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        // Apply .complete file protection to the directory; SwiftData inherits.
        try fm.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: parent.path
        )
    }
}
