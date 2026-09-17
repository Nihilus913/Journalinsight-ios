import Foundation
import Testing
import JICore
@testable import JIFeatures

/// `ChallengesProviding` double — same "can be told to fail" shape as `TrainingFakeProvider`.
nonisolated final class ChallengesFakeProvider: ChallengesProviding, @unchecked Sendable {
    var failing = false
    var error: HubError = .network("simulated")
    var rows: [GateChallenge] = [
        GateChallenge(
            challengeId: 1, title: "Textbook intervals", hypothesis: "h", startDate: "2026-09-01",
            targetSessions: 4, sessionFilter: "interval", status: .active, createdAt: nil, completedAt: nil,
            resultNote: nil, updatedAt: nil,
            progress: ChallengeProgress(count: 1, target: 4, executionScore: 25, pace: "on_pace", wantsCompletePrompt: false)
        ),
        GateChallenge(
            challengeId: 2, title: "Old one", hypothesis: "h2", startDate: "2026-08-01",
            targetSessions: 2, sessionFilter: "interval", status: .archived, createdAt: nil, completedAt: nil,
            resultNote: nil, updatedAt: nil,
            progress: ChallengeProgress(count: 0, target: 2, executionScore: 0, pace: nil, wantsCompletePrompt: false)
        ),
    ]

    func challenges() async throws -> [GateChallenge] { if failing { throw error }; return rows }

    func createChallenge(_ input: ChallengeCreateInput) async throws -> GateChallenge {
        if failing { throw error }
        let row = GateChallenge(
            challengeId: 99, title: input.title, hypothesis: input.hypothesis, startDate: input.startDate,
            targetSessions: input.targetSessions, sessionFilter: input.sessionFilter, status: .active,
            createdAt: nil, completedAt: nil, resultNote: nil, updatedAt: nil,
            progress: ChallengeProgress(count: 0, target: input.targetSessions, executionScore: 0, pace: nil, wantsCompletePrompt: false)
        )
        rows.append(row)
        return row
    }

    func updateChallenge(challengeId: Int, patch: ChallengeUpdatePatch) async throws -> GateChallenge {
        if failing { throw error }
        guard var row = rows.first(where: { $0.challengeId == challengeId }) else { throw HubError.http(status: 404, detail: nil) }
        if let title = patch.title { row.title = title }
        if let hypothesis = patch.hypothesis { row.hypothesis = hypothesis }
        if let targetSessions = patch.targetSessions { row.targetSessions = targetSessions }
        if let startDate = patch.startDate { row.startDate = startDate }
        if let resultNote = patch.resultNote { row.resultNote = resultNote }
        rows[rows.firstIndex(where: { $0.challengeId == challengeId })!] = row
        return row
    }

    func archiveChallenge(challengeId: Int, status: ChallengeArchiveStatus, resultNote: String?) async throws -> GateChallenge {
        if failing { throw error }
        guard var row = rows.first(where: { $0.challengeId == challengeId }) else { throw HubError.http(status: 404, detail: nil) }
        row.status = status == .completed ? .completed : .archived
        if let resultNote { row.resultNote = resultNote }
        rows[rows.firstIndex(where: { $0.challengeId == challengeId })!] = row
        return row
    }

    func deleteChallenge(challengeId: Int) async throws {
        if failing { throw error }
        rows.removeAll { $0.challengeId == challengeId }
    }
}

@Test @MainActor func challengesLoadSplitsActiveAndPast() async throws {
    let vm = ChallengesViewModel(provider: ChallengesFakeProvider())
    await vm.load()
    #expect(vm.phase == .loaded)
    #expect(vm.active.map(\.challengeId) == [1])
    #expect(vm.past.map(\.challengeId) == [2])
}

@Test @MainActor func challengesLoadSurfacesNamedHubErrorOnFailure() async throws {
    let provider = ChallengesFakeProvider()
    provider.failing = true
    provider.error = .unauthorized
    let vm = ChallengesViewModel(provider: provider)
    await vm.load()
    if case .error = vm.phase {} else { Issue.record("expected .error phase") }
    #expect(vm.lastError == .unauthorized)
}

@Test @MainActor func createAppendsRowToList() async throws {
    let vm = ChallengesViewModel(provider: ChallengesFakeProvider())
    await vm.load()
    let result = await vm.create(ChallengeCreateInput(title: "New", hypothesis: "h", startDate: "2026-09-17", targetSessions: 3))
    guard case .success(let row) = result else { Issue.record("expected success"); return }
    #expect(row.challengeId == 99)
    #expect(vm.challenges.contains { $0.challengeId == 99 })
}

@Test @MainActor func archiveThenDeleteRoundTrip() async throws {
    let vm = ChallengesViewModel(provider: ChallengesFakeProvider())
    await vm.load()
    let archived = await vm.archive(challengeId: 1, status: .completed, resultNote: "done")
    guard case .success(let row) = archived else { Issue.record("expected success"); return }
    #expect(row.status == .completed)
    #expect(row.resultNote == "done")

    let deleteErr = await vm.delete(challengeId: 2)
    #expect(deleteErr == nil)
    #expect(vm.challenges.contains { $0.challengeId == 2 } == false)
}

@Test @MainActor func deleteSurfacesNamedHubErrorOnConflict() async throws {
    let provider = ChallengesFakeProvider()
    let vm = ChallengesViewModel(provider: provider)
    await vm.load()
    provider.failing = true
    provider.error = .duplicate(detail: "has recorded sessions")
    let err = await vm.delete(challengeId: 1)
    #expect(err == .duplicate(detail: "has recorded sessions"))
    #expect(vm.challenges.contains { $0.challengeId == 1 }) // never removed on failure
}

@Test @MainActor func editorCreateModeValidatesRequiredFields() async throws {
    let vm = ChallengesViewModel(provider: ChallengesFakeProvider())
    await vm.load()
    let editor = ChallengeEditorViewModel(challenges: vm)
    #expect(editor.isEditing == false)
    #expect(editor.canSubmit == false) // title/hypothesis empty
    editor.title = "Textbook"
    editor.hypothesis = "h"
    #expect(editor.canSubmit)
    editor.startDate = "not-a-date"
    #expect(editor.canSubmit == false)
}

@Test @MainActor func editorEditModeLocksFieldsWhenSessionsRecorded() async throws {
    let vm = ChallengesViewModel(provider: ChallengesFakeProvider())
    await vm.load()
    let existing = vm.active.first(where: { $0.challengeId == 1 })!
    #expect(existing.progress.count > 0)
    let editor = ChallengeEditorViewModel(challenges: vm, existing: existing)
    #expect(editor.canEditLockedFields == false)
    // Still submittable on title-only edits, without needing a valid date.
    editor.title = "Renamed"
    #expect(editor.canSubmit)
}

@Test @MainActor func editorSubmitCreatesAndSurfacesError() async throws {
    let provider = ChallengesFakeProvider()
    let vm = ChallengesViewModel(provider: provider)
    await vm.load()
    let editor = ChallengeEditorViewModel(challenges: vm)
    editor.title = "Textbook"
    editor.hypothesis = "h"
    let created = await editor.submit()
    #expect(created?.challengeId == 99)
    #expect(editor.errorMessage == nil)

    provider.failing = true
    provider.error = .http(status: 422, detail: "target_sessions is locked")
    let editor2 = ChallengeEditorViewModel(challenges: vm)
    editor2.title = "Another"
    editor2.hypothesis = "h2"
    let failed = await editor2.submit()
    #expect(failed == nil)
    #expect(editor2.errorMessage == "target_sessions is locked")
}
