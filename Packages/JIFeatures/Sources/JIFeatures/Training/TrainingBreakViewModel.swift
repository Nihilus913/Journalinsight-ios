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

    private let provider: any TrainingBreakProviding

    public init(provider: any TrainingBreakProviding, state: TrainingBreak? = nil) {
        self.provider = provider
        self.state = state
    }

    public var paused: Bool { state?.paused == true }

    /// "On a break since 28 Sep" while paused; nil otherwise.
    public var sinceText: String? {
        guard paused, let since = state?.since else { return nil }
        return "On a break since \(trainingBreakDayText(since))"
    }

    public func load() async {
        do { state = try await provider.trainingBreak(); errorMessage = nil } catch { errorMessage = "Hub unreachable — the break can't be read right now" }
    }

    /// On = a break from `since` (nil = the hub's today); off = the break ends today.
    public func set(paused: Bool, since: String? = nil) async {
        busy = true
        defer { busy = false }
        do {
            state = try await provider.setTrainingBreak(paused: paused, since: since)
            errorMessage = nil
        } catch {
            errorMessage = "Could not update the break — \(trainingBreakErrorText(error))"
        }
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
