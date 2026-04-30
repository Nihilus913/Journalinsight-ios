// JournalInsight/Sync/SyncStatusObserver.swift
import Foundation
import SwiftData
import CoreData
import os

@MainActor
@Observable
final class SyncStatusObserver {

    private(set) var status: SyncStatus = .syncing

    nonisolated(unsafe) private var token: NSObjectProtocol?

    init() {
        token = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleEventNotification(note)
        }
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }

    private nonisolated func handleEventNotification(_ note: Notification) {
        Task { @MainActor in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            if event.endDate == nil {
                status = .syncing
            } else if let error = event.error {
                ingest(error: error)
            } else {
                ingestSuccess()
            }
        }
    }

    /// Test-friendly entry point that maps an arbitrary error to a SyncStatus case.
    func ingest(error: Error) {
        let nsError = error as NSError
        if nsError.domain == "CKErrorDomain" && nsError.code == 9 {
            status = .paused(.notSignedIntoiCloud)
            return
        }
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            status = .paused(.networkOffline)
            return
        }
        // CKError code 33 corresponds to schemaConflict-ish errors — surface as schemaMismatch.
        if nsError.domain == "CKErrorDomain" && nsError.code == 33 {
            status = .paused(.schemaMismatch)
            return
        }
        status = .error(nsError.localizedDescription)
    }

    func ingestSuccess() {
        status = .idle
    }
}
