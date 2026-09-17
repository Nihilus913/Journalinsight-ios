import Foundation
import Observation
import JICore

/// Backs both the create form and the per-card edit form (oracle: `CreateChallengeForm` /
/// `EditChallengeForm` in `app/challenges.tsx`) — same field set, same `YYYY-MM-DD` validation,
/// same submit-pending/error shape; the only difference is whether `existing` is set. Delegates
/// the actual network call to the shared `ChallengesViewModel` so the list VM stays the single
/// source of truth for the in-memory rows.
@Observable @MainActor
public final class ChallengeEditorViewModel {
    private static let dateRegex = /^\d{4}-\d{2}-\d{2}$/

    public var title: String
    public var hypothesis: String
    public var targetSessions: Int
    public var startDate: String
    public var resultNote: String
    public private(set) var isSubmitting = false
    public private(set) var errorMessage: String?

    private let challenges: ChallengesViewModel
    private let existing: GateChallenge?
    private let now: () -> Date

    /// `existing == nil` → create mode; otherwise edit mode for that row.
    public init(challenges: ChallengesViewModel, existing: GateChallenge? = nil, now: @escaping () -> Date = Date.init) {
        self.challenges = challenges
        self.existing = existing
        self.now = now
        title = existing?.title ?? ""
        hypothesis = existing?.hypothesis ?? ""
        targetSessions = existing?.targetSessions ?? 4
        startDate = existing?.startDate ?? Self.todayIso(now())
        resultNote = existing?.resultNote ?? ""
    }

    public var isEditing: Bool { existing != nil }

    /// Oracle `canEditLockedFields`: target sessions / start date are only editable in create mode
    /// or while the existing challenge is still active with zero recorded sessions.
    public var canEditLockedFields: Bool { existing?.canEditLockedFields ?? true }

    private var dateValid: Bool { startDate.trimmingCharacters(in: .whitespaces).wholeMatch(of: Self.dateRegex) != nil }

    public var canSubmit: Bool {
        guard !isSubmitting else { return false }
        let titleOK = !title.trimmingCharacters(in: .whitespaces).isEmpty
        let hypothesisOK = !hypothesis.trimmingCharacters(in: .whitespaces).isEmpty
        guard titleOK && hypothesisOK else { return false }
        guard canEditLockedFields else { return true }
        return dateValid && targetSessions > 0
    }

    /// Returns the resulting row on success. `nil` on failure (with `errorMessage` set) or when
    /// there is nothing to submit (an edit with no changed fields — mirrors the oracle closing the
    /// form without a network call in that case).
    @discardableResult
    public func submit() async -> GateChallenge? {
        guard canSubmit else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        if let existing {
            let patch = diffPatch(against: existing)
            guard patch.hasAnyField else { return existing }
            switch await challenges.update(challengeId: existing.challengeId, patch: patch) {
            case .success(let row): return row
            case .failure(let err): errorMessage = describeChallengeMutationError(err); return nil
            }
        } else {
            let input = ChallengeCreateInput(
                title: title.trimmingCharacters(in: .whitespaces),
                hypothesis: hypothesis.trimmingCharacters(in: .whitespaces),
                startDate: startDate.trimmingCharacters(in: .whitespaces),
                targetSessions: targetSessions,
                sessionFilter: "interval"
            )
            switch await challenges.create(input) {
            case .success(let row): return row
            case .failure(let err): errorMessage = describeChallengeMutationError(err); return nil
            }
        }
    }

    /// Mirrors the oracle's `EditChallengeForm.submit`: only fields that actually changed go on
    /// the wire, and locked fields are never sent when `canEditLockedFields` is false.
    private func diffPatch(against existing: GateChallenge) -> ChallengeUpdatePatch {
        var patch = ChallengeUpdatePatch()
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedHypothesis = hypothesis.trimmingCharacters(in: .whitespaces)
        let trimmedNote = resultNote.trimmingCharacters(in: .whitespaces)
        let initialNote = existing.resultNote ?? ""
        if trimmedTitle != existing.title { patch.title = trimmedTitle }
        if trimmedHypothesis != existing.hypothesis { patch.hypothesis = trimmedHypothesis }
        if trimmedNote != initialNote { patch.resultNote = trimmedNote }
        if canEditLockedFields {
            if targetSessions != existing.targetSessions { patch.targetSessions = targetSessions }
            let trimmedStart = startDate.trimmingCharacters(in: .whitespaces)
            if trimmedStart != existing.startDate { patch.startDate = trimmedStart }
        }
        return patch
    }

    private static func todayIso(_ date: Date) -> String { String(date.ISO8601Format().prefix(10)) }
}

private extension ChallengeUpdatePatch {
    var hasAnyField: Bool {
        title != nil || hypothesis != nil || targetSessions != nil || startDate != nil || sessionFilter != nil || resultNote != nil
    }
}
