import Foundation
import Observation
import JICore

/// W-B91 (Toby 2026-10-04: "B91 pause should be a manual status") — Settings' "I'm on a break"
/// toggle. The hub holds the state (`GET/PUT /api/v1/planning/training-break`); Decide's Load row
/// reads "Paused" + the start date from the hub's `/morning` while it is on. No outbox: the
/// toggle shows the hub's confirmed state, and a failed write reverts it with the hub's reason.
@Observable @MainActor
public final class TrainingBreakViewModel {
    public private(set) var state: TrainingBreak?
    public private(set) var busy = false
    public private(set) var errorMessage: String?
    /// B-52 p2: when the last read came from the offline cache (hub unreachable), the fetch time of
    /// that copy — the row shows the last-known state with an "Offline — showing data from …" line
    /// instead of an empty, disabled toggle. nil = the hub answered.
    public private(set) var staleSince: Date?

    private let provider: any TrainingBreakProviding

    /// B-107: runs after every confirmed write (the app shell re-fetches Today/Decide so the Load
    /// row reads "Paused" at once, not after a relaunch). Never runs on a failed write.
    @ObservationIgnored public var onChanged: (@MainActor () async -> Void)?

    public init(provider: any TrainingBreakProviding, state: TrainingBreak? = nil,
                onChanged: (@MainActor () async -> Void)? = nil) {
        self.provider = provider
        self.state = state
        self.onChanged = onChanged
    }

    public var paused: Bool { state?.paused == true }

    /// "On a break since 28 Sep" while paused; nil otherwise.
    public var sinceText: String? {
        guard paused, let since = state?.since else { return nil }
        return "On a break since \(trainingBreakDayText(since))"
    }

    /// B-52 p2: reads through the hub's offline cache — offline with a stored copy = that state +
    /// `staleSince`; offline with a cold cache = the explicit error (no fabricated "off").
    public func load() async {
        let provider = self.provider
        do {
            let (value, since) = try await HubReadTrace.collect { try await provider.trainingBreak() }
            state = value; staleSince = since; errorMessage = nil
        } catch {
            errorMessage = state == nil ? "Hub unreachable — the break can't be read right now" : nil
        }
    }

    /// "Offline — showing data from 07:41" while the shown state is the cached copy.
    public var offlineText: String? { staleSince.map { offlineReadCaption(since: $0) } }

    /// On = a break from `since` (nil = the hub's today); off = the break ends today.
    public func set(paused: Bool, since: String? = nil) async {
        busy = true
        defer { busy = false }
        do {
            state = try await provider.setTrainingBreak(paused: paused, since: since)
            errorMessage = nil; staleSince = nil
        } catch {
            errorMessage = "Could not update the break — \(trainingBreakErrorText(error))"
            return
        }
        await onChanged?()
    }
}

nonisolated func trainingBreakErrorText(_ error: Error) -> String {
    switch error as? HubError {
    case .network?: return "hub unreachable"
    case .http(_, let detail?)?: return detail
    default: return "the hub said no"
    }
}

/// "2026-09-28" → "28 Sep" (the hub caption's spelling); unparseable input is returned as is.
public nonisolated func trainingBreakDayText(_ iso: String) -> String {
    let parts = iso.split(separator: "-")
    guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]), (1...12).contains(m) else { return iso }
    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return "\(d) \(months[m - 1])"
}
