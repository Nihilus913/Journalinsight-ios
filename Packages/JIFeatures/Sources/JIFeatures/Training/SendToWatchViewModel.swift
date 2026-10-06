#if canImport(WorkoutKit)
import Foundation
import Observation
import WorkoutKit
import JICore
import JIWorkouts

/// B-37-L3 (P-workouts) — drives the Training "Send to Watch" sheet (spec §3 UI): loads the
/// `plan.workout_template` rows through `WorkoutTemplatesProviding`, keeps a multi-select set and a
/// target date (default today), and `send()` builds one WorkoutKit plan per selected template and
/// schedules it through the `WorkoutSending` seam. Per-workout delivery only — never "send week"
/// (spec §1). The builder is injectable so this lane's tests never wait on L2's real
/// `WorkoutBuilder`; the default is `WorkoutBuilder.build`.
@MainActor @Observable
public final class SendToWatchViewModel {
    public typealias Builder = @Sendable (WorkoutTemplate) throws -> WorkoutPlan

    public enum State: Equatable, Sendable {
        case idle
        case loading
        case sending
        /// `n` plans scheduled on the last `send()`.
        case sent(Int)
        /// `requestAuthorization()` answered `false` — the sheet shows copy + a Settings link.
        case authDenied
        case error(String)
    }

    public private(set) var state: State = .idle
    public private(set) var templates: [WorkoutTemplate] = []
    /// B-52 p2: the list came from the offline read-through cache (hub unreachable) — when that copy
    /// was fetched. Sending still works (WorkoutKit is on the phone); nil = the hub answered.
    public private(set) var staleSince: Date?
    /// B-52 p2: "Offline — showing data from 07:41" while the list is the cached copy.
    public var offlineText: String? { staleSince.map { offlineReadCaption(since: $0) } }
    /// `WorkoutTemplate.templateId`s picked for sending.
    public private(set) var selected: Set<Int> = []
    /// Names scheduled by the last successful `send()`, in template order (the "scheduled" rows).
    public private(set) var sentNames: [String] = []
    /// The day (and time) the plans are scheduled for; default = today.
    public var date: Date

    private let provider: any WorkoutTemplatesProviding
    private let sender: any WorkoutSending
    private let builder: Builder
    private let calendar: Calendar
    /// Auth-denied escape hatch: the app wires `UIApplication.openSettingsURLString` here.
    public let openSettings: () -> Void
    /// B-57 W4: the user's own limits (optional cap, optional Zone 5 avoidance); `.none` = no check.
    public let limits: WorkoutHrLimits
    /// RG-68: the user's zones (gate-settings) — a Zone 2 template's work alert follows them.
    public let zones: HrZones?

    public init(
        provider: any WorkoutTemplatesProviding,
        sender: any WorkoutSending,
        builder: @escaping Builder = WorkoutBuilder.build,
        now: () -> Date = Date.init,
        calendar: Calendar = .current,
        openSettings: @escaping () -> Void = {},
        // B-33 §8.5: `ImageRenderer` runs no `.task`, so the sweep would only ever photograph the
        // pre-load empty state. A seed lets the screenshot entry start from a loaded list; the app
        // never passes it (default `[]`), and `load()` overwrites it on the first real fetch.
        seededTemplates: [WorkoutTemplate] = [],
        limits: WorkoutHrLimits = .none,
        zones: HrZones? = nil
    ) {
        self.limits = limits
        self.zones = zones
        self.provider = provider
        self.sender = sender
        self.builder = builder
        self.calendar = calendar
        self.openSettings = openSettings
        self.date = now()
        self.templates = seededTemplates.filter(sendToWatchCanBuild)
    }

    public func load() async {
        state = .loading
        do {
            // W-B88: a strength-only template (a strength day, post-073) cannot become a WorkoutKit
            // plan (`noCardioSegment`) — never listed; strength reaches the Watch from the Planner.
            let provider = self.provider
            let (rows, since) = try await HubReadTrace.collect { try await provider.workoutTemplates() }
            templates = rows.filter(sendToWatchCanBuild)
            staleSince = since
            selected = selected.intersection(templates.map(\.templateId))
            state = .idle
        } catch {
            // Cold cache + hub unreachable: an honest error, never a fabricated list. A list
            // already on screen (an earlier load) stays — the error only says the refresh failed.
            if templates.isEmpty { staleSince = nil }
            guard templates.isEmpty else { state = .error(describe(error)); return }
            templates = []
            state = .error(describe(error))
        }
    }

    public func toggle(_ templateId: Int) {
        if selected.contains(templateId) { selected.remove(templateId) } else { selected.insert(templateId) }
    }

    /// B40-V7: the library row's "Send to Watch" — that workout, and only it, is picked.
    public func pickOnly(_ templateId: Int) { selected = [templateId] }

    public func isSelected(_ templateId: Int) -> Bool { selected.contains(templateId) }

    public var isBusy: Bool { state == .loading || state == .sending }

    /// The send button's enabled state: something picked and nothing in flight.
    public var canSend: Bool { !selected.isEmpty && !isBusy }

    /// Human copy for the status row under the list (empty when there is nothing to say).
    public var statusMessage: String {
        switch state {
        case .idle, .loading: ""
        case .sending: "Sending to Watch…"
        case .sent(let n): n == 1 ? "1 workout scheduled." : "\(n) workouts scheduled."
        case .authDenied: "Workout scheduling isn't allowed. Enable it for JournalInsight in Settings › Privacy › Workouts."
        case .error(let msg): msg
        }
    }

    /// Builds + schedules one plan per selected template (template order). No-op when nothing is
    /// selected. Any failure — builder (e.g. the 175 cap), authorization, or the scheduler — leaves
    /// the selection untouched so the user can retry.
    public func send() async {
        guard canSend else { return }
        state = .sending
        let picked = templates.filter { selected.contains($0.templateId) }
        let at = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        do {
            guard try await sender.requestAuthorization() else {
                state = .authDenied
                return
            }
            // Build every plan first so a cap violation schedules nothing at all.
            let plans = try picked.map { (name: $0.name, plan: try builder(sendToWatchApplyingZones($0, zones: zones))) }
            for entry in plans { try await sender.schedule(entry.plan, at: at) }
            sentNames = plans.map(\.name)
            state = .sent(plans.count)
        } catch {
            state = .error(describe(error))
        }
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case HubError.unauthorized: "Hub rejected the token — check Settings › Connection."
        case let e as HubError: "Hub error: \(e)"
        case WorkoutBuilderError.capExceeded(let bpm):
            "A step targets \(bpm) bpm — above your \(limits.capBpm.map(String.init) ?? "—") bpm cap. Fix the template on the hub."
        case WorkoutBuilderError.zone5Target(let bpm, let floor):
            "A step targets \(bpm) bpm — inside your Zone 5 (from \(floor)), which you chose to avoid. Fix the template on the hub."
        case WorkoutBuilderError.notImplemented: "Workout builder not available in this build."
        default: "Couldn't send: \(error.localizedDescription)"
        }
    }
}

/// W-B88: WorkoutKit can run the template — it has a cardio segment (or is a pre-053 row with no
/// segments, its compat `steps` = one running segment). All-strength = `noCardioSegment`.
public nonisolated func sendToWatchCanBuild(_ t: WorkoutTemplate) -> Bool {
    t.segments.isEmpty || t.segments.contains { $0.sport.isCardio }
}

/// SendToWatch footer. The cap part appears only when the user set a cap.
/// W-FIX10 F10-3 (B40 obs 3): Bevel is retired (B-38 / B-40) — strength is logged in JI.
public nonisolated func sendToWatchAlertNote(_ limits: WorkoutHrLimits) -> String {
    "Cardio only — strength parts are logged in JournalInsight, not sent. Heart-rate alerts are absolute bpm"
        + (limits.capBpm.map { ", capped at your \($0) bpm" } ?? "")
        + (limits.zone5FloorBpm.map { ", below your Zone 5 (\($0))" } ?? "") + "."
}
#endif

// MARK: - RG-68 (W-FIX-P3): a "Zone 2" template alerts on the USER's Zone 2

/// RG-68: true for a template whose name says it is a Zone 2 session ("Zone 2 40 min", "Long Run
/// Zone 2", "Z2 …"). Only these have their work alert re-anchored on the user's zones.
nonisolated func sendToWatchIsZone2(_ t: WorkoutTemplate) -> Bool {
    let n = t.name.lowercased()
    return n.contains("zone 2") || n.range(of: #"\bz2\b"#, options: .regularExpression) != nil
}

/// RG-68: the copy sent to the Watch — a Zone 2 template's `work` steps alert on the user's own
/// Zone 2 (gate-settings floors, B-57 W4: zones are the user's, never constants). Send-time only:
/// the hub row is not rewritten. No (valid) zones or not a Zone 2 template = unchanged.
public nonisolated func sendToWatchApplyingZones(_ t: WorkoutTemplate, zones: HrZones?) -> WorkoutTemplate {
    guard sendToWatchIsZone2(t), let zones, zones.isValid else { return t }
    let z2 = zones.floorsBpm[1]...(zones.floorsBpm[2] - 1)
    var out = t
    out.segments = t.effectiveSegments.map { seg in
        guard seg.sport.isCardio else { return seg }
        return WorkoutSegment(sport: seg.sport, steps: seg.steps.map { step in
            guard var c = step.cardio, c.purpose == .work else { return step }
            c.target = .hrRange(lo: z2.lowerBound, hi: z2.upperBound)
            return .cardio(c)
        })
    }
    if out.segments == t.effectiveSegments, t.segments.isEmpty { return t }
    return out
}

/// RG-68: the range the Watch alerts on during the main part — the work steps' span (warm-up and
/// cool-down excluded), after `sendToWatchApplyingZones`. nil = no absolute target.
public nonisolated func sendToWatchAlertRange(_ t: WorkoutTemplate, zones: HrZones?) -> ClosedRange<Int>? {
    let cardio = sendToWatchApplyingZones(t, zones: zones).effectiveSegments.flatMap { $0.steps.compactMap(\.cardio) }
    let work = cardio.filter { $0.purpose == .work }
    var los: [Int] = [], his: [Int] = []
    for s in (work.isEmpty ? cardio : work) {
        switch s.target {
        case .hrRange(let lo, let hi): los.append(lo); his.append(hi)
        case .hrZone(let z):
            if let zones, zones.isValid, (1...4).contains(z) { los.append(zones.floorsBpm[z - 1]); his.append(zones.floorsBpm[z] - 1) }
        case .none: break
        }
    }
    guard let lo = los.min(), let hi = his.max() else { return nil }
    return lo...hi
}

/// RG-68: the Send-to-Watch row line — "40 min · 3 steps · alert 117–138 bpm" (the work alert,
/// not the warm-up's 100–140 span the library line shows).
public nonisolated func sendToWatchRowSummary(_ t: WorkoutTemplate, zones: HrZones?) -> String {
    let base = WorkoutFormat.summary(t)
    guard !t.hasStrength, let r = sendToWatchAlertRange(t, zones: zones) else { return base }
    let parts = base.components(separatedBy: " · ").filter { !$0.hasSuffix("bpm") && !$0.hasPrefix("Zone") }
    return (parts + ["alert \(r.lowerBound)–\(r.upperBound) bpm"]).joined(separator: " · ")
}
