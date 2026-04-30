// JournalInsightTests/SyncStatusObserverTests.swift
import Testing
import Foundation
@testable import JournalInsight

@MainActor
@Suite("SyncStatusObserver")
struct SyncStatusObserverTests {

    @Test("Initial status is syncing")
    func initial() {
        let obs = SyncStatusObserver()
        #expect(obs.status == .syncing)
    }

    @Test("Reports notSignedIntoiCloud when ingest sees CKError code 9 (notAuthenticated) family")
    func notSignedIn() {
        let obs = SyncStatusObserver()
        obs.ingest(error: NSError(domain: "CKErrorDomain", code: 9, userInfo: nil))
        #expect(obs.status == .paused(.notSignedIntoiCloud))
    }

    @Test("Reports networkOffline on URLError.notConnectedToInternet")
    func networkOffline() {
        let obs = SyncStatusObserver()
        obs.ingest(error: URLError(.notConnectedToInternet))
        #expect(obs.status == .paused(.networkOffline))
    }

    @Test("ingestSuccess returns to idle")
    func successReturnsIdle() {
        let obs = SyncStatusObserver()
        obs.ingest(error: URLError(.notConnectedToInternet))
        obs.ingestSuccess()
        #expect(obs.status == .idle)
    }
}
