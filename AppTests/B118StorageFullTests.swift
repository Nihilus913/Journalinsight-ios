import Foundation
import Testing
import JIFeatures
import JIHub
@testable import JournalInsight

// RG-02 / B-118: a failing SQLite open at launch (disk full, sandbox I/O error) used to hit
// `fatalError("AppEnvironment init failed…")`. It now lands in `.storageFull` with an in-memory
// (hub-only read) environment, and the failure is written to the CrashLog ("Last crash").
@Suite struct B118StorageFullTests {
    struct OpenFailure: Error, CustomStringConvertible { var description: String { "SQLite error 13: database or disk is full" } }

    private func scratchStore() -> CrashLogStore {
        CrashLogStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("B118-\(UUID().uuidString)", isDirectory: true))
    }

    @Test @MainActor func injectedOpenFailureLandsInStorageFullNotATrap() throws {
        let store = scratchStore()
        let result = AppEnvironmentBootstrap.make(
            forceStorageFull: false,
            onDisk: { throw OpenFailure() },
            inMemory: { try AppEnvironment(secrets: InMemorySecretStore(), inMemory: true) },
            crashStore: store, info: VersionInfo(appName: "JI", appVersion: "1.0", build: "1", bundleId: "x"))
        guard case .storageFull(let reason) = result.state else { Issue.record("expected .storageFull, got \(result.state)"); return }
        #expect(reason.contains("disk is full"))
        #expect(result.env != nil, "hub-only read mode keeps an in-memory environment")
    }

    @Test @MainActor func openFailureIsWrittenToTheCrashLog() throws {
        let store = scratchStore()
        _ = AppEnvironmentBootstrap.make(
            forceStorageFull: false,
            onDisk: { throw OpenFailure() },
            inMemory: { try AppEnvironment(secrets: InMemorySecretStore(), inMemory: true) },
            crashStore: store, info: VersionInfo(appName: "JI", appVersion: "1.0", build: "1", bundleId: "x"))
        let latest = try #require(store.latest)
        #expect(latest.type == "StorageFull")
        #expect(latest.summary.contains("disk is full"))
    }

    @Test @MainActor func bothOpensFailingStillDoesNotTrap() {
        let result = AppEnvironmentBootstrap.make(
            forceStorageFull: false,
            onDisk: { throw OpenFailure() }, inMemory: { throw OpenFailure() },
            crashStore: scratchStore(), info: VersionInfo(appName: "JI", appVersion: "1.0", build: "1", bundleId: "x"))
        #expect(result.env == nil)
        if case .storageFull = result.state {} else { Issue.record("expected .storageFull") }
    }

    @Test @MainActor func healthyOpenIsReady() {
        let store = scratchStore()
        let result = AppEnvironmentBootstrap.make(
            forceStorageFull: false,
            onDisk: { try AppEnvironment(secrets: InMemorySecretStore(), inMemory: true) },
            inMemory: { throw OpenFailure() },
            crashStore: store, info: VersionInfo(appName: "JI", appVersion: "1.0", build: "1", bundleId: "x"))
        #expect(result.state == .ready)
        #expect(result.env != nil)
        #expect(store.latest == nil)
    }

    @Test @MainActor func forceFlagSimulatesTheFailure() {
        let result = AppEnvironmentBootstrap.make(
            forceStorageFull: true,
            onDisk: { try AppEnvironment(secrets: InMemorySecretStore(), inMemory: true) },
            inMemory: { try AppEnvironment(secrets: InMemorySecretStore(), inMemory: true) },
            crashStore: scratchStore(), info: VersionInfo(appName: "JI", appVersion: "1.0", build: "1", bundleId: "x"))
        if case .storageFull = result.state {} else { Issue.record("expected .storageFull") }
    }

    @Test func forceFlagReadsTheLaunchArgument() {
        #expect(AppEnvironmentBootstrap.forceStorageFullRequested(["app", "-JIForceStorageFull", "YES"]))
        #expect(!AppEnvironmentBootstrap.forceStorageFullRequested(["app"]))
        #expect(!AppEnvironmentBootstrap.forceStorageFullRequested(["app", "-JIForceStorageFull", "NO"]))
    }
}
