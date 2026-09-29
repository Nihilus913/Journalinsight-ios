import Foundation
import Observation
import JICore

/// One step row in the editor (stable identity for `ForEach` / move / delete).
public struct EditableStep: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var step: SegmentStep
    public init(id: UUID = UUID(), step: SegmentStep) { self.id = id; self.step = step }
}

public struct EditableSegment: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var sport: WorkoutSport
    public var steps: [EditableStep]
    public init(id: UUID = UUID(), sport: WorkoutSport, steps: [EditableStep]) { self.id = id; self.sport = sport; self.steps = steps }
}

/// W-B40 L2 (B-40b-3, spec §4) — the template editor's model: name, description, location,
/// segments with cardio step rows (purpose, end, target, repeat) and strength step rows
/// (exercise, sets, reps | seconds, kg, rest). Sheet + `@Bindable` model + `onSave`, the same
/// shape as the app's other edit sheets. Weekdays are shown, not edited — they are B-45's
/// plan-session assignment (spec §10.3; B-82 is where a day gets its workout).
///
/// Validation mirrors the hub's Pydantic rules (spec §2.1 / §3) so a draft the hub would refuse
/// is caught here instead of being queued and retired: the hub stays the validator of record, the
/// 175 bpm ceiling is enforced there, and here only defensively.
@MainActor
@Observable
public final class WorkoutEditorViewModel {
    /// Spec §2.1 `hi ≤ 175` (HT enforces it on write; Swift checks defensively only).
    public nonisolated static let hubHrCeiling = 175

    public var name: String
    public var descriptionText: String
    public var location: WorkoutLocation
    public var segments: [EditableSegment]
    public private(set) var isSaving = false
    public private(set) var errorText: String?

    public let original: WorkoutTemplate?
    /// W-FIX10 F10-3 (B40 obs 1): the draft as stored, to tell an edit from no change (nil = new).
    private var storedDraft: WorkoutTemplateDraft?
    public let weekdays: [Int]
    public let exerciseOptions: [ExerciseOption]
    private let onSave: (WorkoutTemplateDraft) async -> WorkoutLibraryViewModel.SaveResult

    public init(template: WorkoutTemplate?, exerciseOptions: [ExerciseOption] = WorkoutExerciseCatalogue.known,
                onSave: @escaping (WorkoutTemplateDraft) async -> WorkoutLibraryViewModel.SaveResult) {
        original = template
        name = template?.name ?? ""
        descriptionText = template?.description ?? ""
        location = template?.location ?? .outdoor
        weekdays = template?.weekdays ?? []
        segments = (template?.effectiveSegments ?? []).map { seg in
            EditableSegment(sport: seg.sport, steps: seg.steps.map { EditableStep(step: $0) })
        }
        if template == nil {
            segments = [EditableSegment(sport: .running, steps: [EditableStep(step: .cardio(Self.newCardioStep()))])]
        }
        self.exerciseOptions = exerciseOptions
        self.onSave = onSave
        storedDraft = template == nil ? nil : draft
    }

    public var isNew: Bool { original == nil }
    public var title: String { isNew ? "New workout" : "Edit workout" }

    public var hasCardio: Bool { segments.contains { $0.sport.isCardio && !$0.steps.isEmpty } }

    /// Spec §4: the Watch send is cardio-only.
    public var watchDisabledReason: String? {
        hasCardio ? nil : "Strength has no Apple Watch workout type — it is logged in JournalInsight (B-38)."
    }

    // MARK: validation

    public var validationIssues: [String] {
        var issues: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Give the workout a name.") }
        if segments.isEmpty || segments.allSatisfy({ $0.steps.isEmpty }) { issues.append("Add at least one step.") }
        for (si, seg) in segments.enumerated() {
            let label = segments.count > 1 ? "Part \(si + 1): " : ""
            if seg.steps.isEmpty { issues.append("\(label)add a step or remove this part.") }
            for (i, row) in seg.steps.enumerated() {
                switch row.step {
                case .cardio(let c):
                    if let issue = Self.issue(c) { issues.append("\(label)step \(i + 1): \(issue)") }
                    if seg.sport == .strength, c.purpose == .work || c.purpose == .recovery {
                        issues.append("\(label)step \(i + 1): a strength part only takes a cardio warm-up or cool-down.")
                    }
                    if c.repeat > 1, !Self.isIntervalPair(seg.steps.map(\.step), at: i) {
                        issues.append("\(label)step \(i + 1): repeats need a work step followed by a recovery step with the same count.")
                    }
                case .strength(let s):
                    if seg.sport != .strength { issues.append("\(label)step \(i + 1): exercises belong in a strength part.") }
                    if let issue = Self.issue(s) { issues.append("\(label)step \(i + 1): \(issue)") }
                }
            }
        }
        return issues
    }

    /// W-FIX10 F10-3 (B40 obs 1): Save waits for a change on an existing workout (a new one is
    /// always a change).
    public var hasChanges: Bool { storedDraft.map { $0 != draft } ?? true }

    public var canSave: Bool { hasChanges && validationIssues.isEmpty && !isSaving }

    nonisolated static func issue(_ c: CardioStep) -> String? {
        switch c.end {
        case .time(let s) where s <= 0: return "set a duration."
        case .distance(let m) where m <= 0: return "set a distance."
        default: break
        }
        switch c.target {
        case .hrRange(let lo, let hi):
            if lo <= 0 || lo >= hi { return "the low heart rate must be below the high one." }
            if hi > hubHrCeiling { return "heart-rate targets stop at \(hubHrCeiling) bpm." }
        case .hrZone(let z) where !(1...5).contains(z): return "pick a zone from 1 to 5."
        default: break
        }
        if c.repeat < 1 { return "repeat at least once." }
        return nil
    }

    nonisolated static func issue(_ s: StrengthStep) -> String? {
        if s.sets < 1 { return "at least one set." }
        switch (s.reps, s.seconds) {
        case (let r?, nil) where r >= 1: break
        case (nil, let t?) where t > 0: break
        default: return "set reps or a time per set."
        }
        if let kg = s.weightKg, kg <= 0 { return "leave the weight empty for bodyweight." }
        return nil
    }

    /// B-37 interval rule: `work`(n) immediately followed by `recovery`(n), n > 1.
    nonisolated static func isIntervalPair(_ steps: [SegmentStep], at i: Int) -> Bool {
        guard let c = steps[i].cardio else { return false }
        if c.purpose == .work, i + 1 < steps.count, let next = steps[i + 1].cardio {
            return next.purpose == .recovery && next.repeat == c.repeat
        }
        if c.purpose == .recovery, i > 0, let prev = steps[i - 1].cardio {
            return prev.purpose == .work && prev.repeat == c.repeat
        }
        return false
    }

    // MARK: editing

    public nonisolated static func newCardioStep(_ purpose: WorkoutStepPurpose = .work) -> CardioStep {
        CardioStep(purpose: purpose, end: .time(seconds: 600), target: .none)
    }

    public func addSegment(_ sport: WorkoutSport) {
        let first: SegmentStep = sport == .strength
            ? .strength(Self.newStrengthStep(exerciseOptions.first))
            : .cardio(Self.newCardioStep())
        segments.append(EditableSegment(sport: sport, steps: [EditableStep(step: first)]))
    }

    public func removeSegment(_ id: UUID) { segments.removeAll { $0.id == id } }

    public func setSport(_ sport: WorkoutSport, of segmentId: UUID) {
        guard let i = segments.firstIndex(where: { $0.id == segmentId }) else { return }
        segments[i].sport = sport
    }

    public func addCardioStep(to segmentId: UUID, purpose: WorkoutStepPurpose = .work) {
        guard let i = segments.firstIndex(where: { $0.id == segmentId }) else { return }
        segments[i].steps.append(EditableStep(step: .cardio(Self.newCardioStep(purpose))))
    }

    public func addStrengthStep(to segmentId: UUID) {
        guard let i = segments.firstIndex(where: { $0.id == segmentId }) else { return }
        segments[i].steps.append(EditableStep(step: .strength(Self.newStrengthStep(exerciseOptions.first))))
    }

    public nonisolated static func newStrengthStep(_ option: ExerciseOption?) -> StrengthStep {
        StrengthStep(exerciseKey: option?.key ?? "", garminCategory: option?.garminCategory ?? "",
                     garminExercise: option?.garminExercise, sets: 3, reps: 10)
    }

    public func removeSteps(at offsets: IndexSet, in segmentId: UUID) {
        guard let i = segments.firstIndex(where: { $0.id == segmentId }) else { return }
        segments[i].steps.remove(atOffsets: offsets)
    }

    public func moveSteps(from source: IndexSet, to destination: Int, in segmentId: UUID) {
        guard let i = segments.firstIndex(where: { $0.id == segmentId }) else { return }
        segments[i].steps.move(fromOffsets: source, toOffset: destination)
    }

    public func step(_ id: UUID) -> SegmentStep? {
        for seg in segments { if let row = seg.steps.first(where: { $0.id == id }) { return row.step } }
        return nil
    }

    /// Replace one step. Setting a work step's repeat carries it to the recovery step right after
    /// it (and vice versa) so an interval pair stays a pair.
    public func update(_ id: UUID, to newStep: SegmentStep) {
        for si in segments.indices {
            guard let i = segments[si].steps.firstIndex(where: { $0.id == id }) else { continue }
            let old = segments[si].steps[i].step
            segments[si].steps[i].step = newStep
            if let o = old.cardio, let n = newStep.cardio, o.repeat != n.repeat {
                let partner = n.purpose == .work ? i + 1 : (n.purpose == .recovery ? i - 1 : -1)
                if segments[si].steps.indices.contains(partner), var p = segments[si].steps[partner].step.cardio,
                   (n.purpose == .work && p.purpose == .recovery) || (n.purpose == .recovery && p.purpose == .work) {
                    p.repeat = n.repeat
                    segments[si].steps[partner].step = .cardio(p)
                }
            }
            return
        }
    }

    // MARK: save

    public var draft: WorkoutTemplateDraft {
        let desc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cardioSport = segments.first(where: { $0.sport.isCardio })?.sport.rawValue
        // Weekdays + gated id ride along unchanged: the hub's PUT is a full replace.
        return WorkoutTemplateDraft(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            activity: cardioSport ?? original?.activity ?? "running",
            location: location,
            description: desc.isEmpty ? nil : desc,
            segments: segments.map { WorkoutSegment(sport: $0.sport, steps: $0.steps.map(\.step)) },
            weekdays: original?.weekdays ?? [],
            gatedTemplateId: original?.gatedTemplateId)
    }

    /// true = the sheet can close (saved, or queued on this phone).
    public func save() async -> Bool {
        guard hasChanges else { errorText = nil; return true }   // nothing to write: just close
        guard canSave else { errorText = validationIssues.first; return false }
        isSaving = true
        defer { isSaving = false }
        errorText = nil
        switch await onSave(draft) {
        case .saved, .queued: return true
        case .refused(let why): errorText = why; return false
        }
    }
}
