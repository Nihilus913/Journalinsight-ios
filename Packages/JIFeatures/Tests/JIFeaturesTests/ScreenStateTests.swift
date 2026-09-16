import Foundation
import Testing
import JICore
@testable import JIFeatures

@Test func screenStateResolvesNeverSyncedOnFirstEverEmptyResponse() {
    let state = ScreenState.resolve(phase: .empty, neverSynced: true, verdictDate: nil, todayDateString: "2026-09-13", lastError: nil)
    #expect(state == .neverSynced)
}

@Test func screenStateResolvesPlainEmptyWhenPreviouslySynced() {
    // Same phase (`.empty`) as the never-synced case above — `neverSynced` alone must be what tells
    // them apart, since a transient blank spell on an established screen isn't a fresh install.
    let state = ScreenState.resolve(phase: .empty, neverSynced: false, verdictDate: nil, todayDateString: "2026-09-13", lastError: nil)
    #expect(state == .empty)
}

@Test func screenStateResolvesStaleVerdictDateWhenVerdictIsFromAnEarlierDay() {
    let state = ScreenState.resolve(phase: .loaded, neverSynced: false, verdictDate: "2026-09-12", todayDateString: "2026-09-13", lastError: nil)
    #expect(state == .staleVerdictDate("2026-09-12"))
}

@Test func screenStateStaysLoadedWhenVerdictDateMatchesToday() {
    let state = ScreenState.resolve(phase: .loaded, neverSynced: false, verdictDate: "2026-09-13", todayDateString: "2026-09-13", lastError: nil)
    #expect(state == .loaded)
}

@Test func screenStateStaysLoadedWhenVerdictDateIsAbsent() {
    // No verdict date to judge staleness against — never fabricate a banner from missing data.
    let state = ScreenState.resolve(phase: .loaded, neverSynced: false, verdictDate: nil, todayDateString: "2026-09-13", lastError: nil)
    #expect(state == .loaded)
}

@Test func screenStateSurfacesYazioAuthExpiredRegardlessOfPhase() {
    // CLAUDE.md rule 4 / DESIGN-7: a named hub error is a UI contract — it must win over whatever
    // `phase` landed on, whether that's an otherwise-happy `.loaded` or an already-failed `.error`.
    let loadedButExpired = ScreenState.resolve(phase: .loaded, neverSynced: false, verdictDate: "2026-09-13", todayDateString: "2026-09-13", lastError: .yazioAuthExpired(detail: "token stale"))
    #expect(loadedButExpired == .yazioAuthExpired(detail: "token stale"))

    let erroredButExpired = ScreenState.resolve(phase: .error("network down"), neverSynced: false, verdictDate: nil, todayDateString: "2026-09-13", lastError: .yazioAuthExpired(detail: "token stale"))
    #expect(erroredButExpired == .yazioAuthExpired(detail: "token stale"))
}

@Test func screenStatePassesThroughIdleLoadingAndErrorUnchanged() {
    #expect(ScreenState.resolve(phase: .idle, neverSynced: false, verdictDate: nil, todayDateString: "2026-09-13", lastError: nil) == .idle)
    #expect(ScreenState.resolve(phase: .loading, neverSynced: false, verdictDate: nil, todayDateString: "2026-09-13", lastError: nil) == .loading)
    #expect(ScreenState.resolve(phase: .error("boom"), neverSynced: false, verdictDate: nil, todayDateString: "2026-09-13", lastError: nil) == .error("boom"))
}
