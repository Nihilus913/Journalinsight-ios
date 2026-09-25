import Foundation
import Observation
import JICore
import JIPersistence

/// Energy tab view model (W3a-L1). Mirrors `RecoveryViewModel`'s phase discipline (CODE-1 /
/// PARITY-7 — named the pattern to follow in the wave card), extended to two independently
/// loaded sections (`energy` report + `goals`, PARITY-7) the way `TodayViewModel` combines three.
@Observable @MainActor
public final class EnergyViewModel {
    public enum Phase: Equatable, Sendable { case idle, loading, loaded, empty, error(String) }

    public private(set) var phase: Phase = .idle
    public private(set) var report: EnergyReport?
    public private(set) var goals: Goals?
    public private(set) var fetchedAt: Date?
    public private(set) var hubReachable = true
    /// See `RecoveryViewModel.hasLiveResult`'s doc comment — same CODE-1 contract.
    public private(set) var hasLiveResult = false
    public private(set) var lastError: HubError?

    private let provider: any EnergyProviding
    private let cache: OfflineCache
    /// Injected clock (tests); the view reads it for "today" in the week and the log.
    public let now: () -> Date
    private static let keys = (energy: "energy.report", goals: "energy.goals")
    private var everSynced = false
    private var neverSyncedObserved = false

    public var onSectionUpdate: (() -> Void)?

    public init(provider: any EnergyProviding, cache: OfflineCache, now: @escaping () -> Date = Date.init) {
        self.provider = provider; self.cache = cache; self.now = now
    }

    public var screenState: ScreenState {
        ScreenState.resolve(
            phase: mappedPhase,
            neverSynced: neverSyncedObserved,
            verdictDate: latestDate,
            todayDateString: todayDateString,
            lastError: lastError
        )
    }

    private var mappedPhase: TodayViewModel.Phase {
        switch phase {
        case .idle: .idle
        case .loading: .loading
        case .loaded: .loaded
        case .empty: .empty
        case .error(let message): .error(message)
        }
    }

    private var latestDate: String? { report?.days.map(\.date).max() }
    private var todayDateString: String { String(now().ISO8601Format().prefix(10)) }

    /// The user's calorie goal from the goals document — the dashed line on "This week" and the
    /// Daily log's status. `nil` = not set (the screen says "No goal set").
    public var goalKcal: Double? { goals?.nutrition.kcalGoal }

    /// The report's days, as the hub sends them — "This week" and the Daily log sort for themselves.
    public var days: [EnergyDay] { report?.days ?? [] }

    public func load() async {
        phase = .loading
        restoreFromCache()
        await fetchLive()
    }

    public func refresh() async { await fetchLive() }

    private func restoreFromCache() {
        if let hit = try? cache.get(Self.keys.energy, as: EnergyReport.self) {
            report = hit.value; fetchedAt = hit.fetchedAt; everSynced = true
        }
        if let hit = try? cache.get(Self.keys.goals, as: Goals.self) { goals = hit.value }
        if report != nil { phase = .loaded }
        if report != nil || goals != nil { onSectionUpdate?() }
    }

    private func fetchLive() async {
        let hadEverSynced = everSynced
        do {
            let provider = self.provider
            let cache = self.cache
            async let eR = SectionLoader.load(key: Self.keys.energy, cache: cache) { try await provider.energy(windowDays: 7) }
            async let gR = SectionLoader.load(key: Self.keys.goals, cache: cache) { try await provider.goals() }
            let (e, g) = try await (eR, gR)

            if let ev = e.value { report = ev }
            if let gv = g.value { goals = gv }
            fetchedAt = e.fetchedAt ?? fetchedAt

            // Same representative-error precedence as TodayViewModel.fetchLive: unauthorized, then
            // network, then whatever else — never masked by a sibling section's own error.
            let sectionErrors = [e.error, g.error].compactMap { $0 }
            let representative = sectionErrors.first { if case .unauthorized = $0 { return true }; return false }
                ?? sectionErrors.first { if case .network = $0 { return true }; return false }
                ?? sectionErrors.first
            lastError = representative

            switch representative {
            case .some(.unauthorized):
                hubReachable = true
                phase = .error(Self.describe(representative!))
            case .some(.network):
                hubReachable = false
                phase = (report == nil) ? .error(Self.describe(representative!)) : .loaded
            case .some(let err):
                hubReachable = true
                phase = (report == nil) ? .error(Self.describe(err)) : .loaded
            case .none:
                hubReachable = true
                hasLiveResult = true
                everSynced = true
                let isEmpty = (report?.days.isEmpty ?? true)
                neverSyncedObserved = isEmpty && !hadEverSynced
                phase = isEmpty ? .empty : .loaded
            }
            onSectionUpdate?()
        } catch {
            // A tab switch cancels the view's `.task`; not a hub outage — mirrors
            // RecoveryViewModel.fetchLive's cancellation branch verbatim.
            if Task.isCancelled { if phase == .loading { phase = .idle }; return }
            lastError = (error as? HubError) ?? .decoding("\(error)")
            hubReachable = true
            phase = (report == nil) ? .error(Self.describe(error)) : .loaded
            onSectionUpdate?()
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error as? HubError {
        case .unauthorized: "Hub rejected the token — check Settings › Connection."
        case .network: "Hub unreachable — is the Mac awake and on the same network?"
        case .some(let e): "Hub error: \(e)"
        case .none: "Unexpected error: \(error.localizedDescription)"
        }
    }
}
