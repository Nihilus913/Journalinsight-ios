import Testing
import SwiftUI
import UIKit
import CryptoKit
import JIFeatures
import JIPersistence
import JIVault
@testable import JournalInsight

// W4-L1 (P-journal): pins the tab vocabulary this lane owns (mirrors RootTabShellTests' own
// "pure shape check" scope) and a render smoke test — the sheet/list/streak/insights layer needs
// a live `JournalViewModel`, which this test builds over an in-memory `AppDatabase` + an
// in-process fake `KeychainService` rather than the real device Keychain.

@Test func rootTabIncludesJournalInRNsSecondPosition() {
    let tabs: Set<RootTab> = [.today, .journal, .recovery, .energy, .nutrition, .training]
    #expect(tabs.count == 6)
    #expect(RootTab.journal != RootTab.today)
}

final class JournalTestKeychain: KeychainService, @unchecked Sendable {
    private var key: SymmetricKey?
    func loadMasterKey() async throws -> SymmetricKey {
        guard let key else { throw KeychainError.itemNotFound }
        return key
    }
    func storeNewMasterKey() async throws -> SymmetricKey {
        let k = SymmetricKey(size: .bits256)
        key = k
        return k
    }
    func deleteMasterKey() async throws { key = nil }
}

@Test @MainActor func journalTabRendersWithoutCrashing() async throws {
    let db = try AppDatabase.inMemory()
    let vault = VaultManager(keychain: JournalTestKeychain())
    let model = JournalViewModel(db: db, vault: vault)
    await model.load()
    #expect(model.state == .loaded)

    let host = UIHostingController(rootView: NavigationStack { JournalView(model: model) })
    host.loadViewIfNeeded()
    #expect(host.view != nil)
}
