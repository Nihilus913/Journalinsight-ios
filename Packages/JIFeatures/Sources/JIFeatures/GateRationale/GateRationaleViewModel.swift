import Foundation
import Observation
import JICore

/// One column of the decision trail (oracle `app/gate-rationale.tsx`'s trail row). Pure data so the
/// trail's ordering, tone bucketing and metric line are testable without a view.
nonisolated public struct GateTrailDay: Equatable, Sendable, Identifiable {
    public let date: String
    public let hrvWeeklyAvg: Double?
    public let rhrBpm: Double?
    public let sleepScore: Double?
    public let tone: VerdictTone
    public var id: String { date }

    /// Oracle: `[HRV x, RHR y, Sleep z].filter(Boolean).join(" · ")`, or the em dash when the day
    /// has none of the three. Never a zero for missing data (CLAUDE.md rule 5).
    public func metricsLine(locale: Locale = .autoupdatingCurrent) -> String {
        let parts = [
            hrvWeeklyAvg.map { "HRV \(Self.num($0, locale))" },
            rhrBpm.map { "RHR \(Self.num($0, locale))" },
            sleepScore.map { "Sleep \(Self.num($0, locale))" },
        ].compactMap { $0 }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    /// The hub sends these as JSON numbers that are whole in practice; RN interpolates them raw, so
    /// a fractional value must not be silently rounded away — 0…1 fraction digits keeps both honest.
    private static func num(_ v: Double, _ locale: Locale) -> String {
        v.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }
}

/// One row of the board's "Last 3 days" table: the verdict persisted for that exact date, or nil
/// (the view shows "—" + "No data") when `morning_go.py` did not run that day.
nonisolated public struct GateDayRow: Equatable, Sendable, Identifiable {
    public let date: String
    /// "Wed 23".
    public let dayLabel: String
    public let session: String?
    /// The user-facing word (`verdictUserWord`), or nil when no verdict was persisted that day.
    public let verdictWord: String?
    public let tone: VerdictTone
    /// W-FIX1 BUG-03: the hub's reduced prescription on an auto-regulated day (from that day's
    /// persisted `reason`), nil otherwise.
    public var prescription: String? = nil
    public var id: String { date }
}

/// Gate-rationale screen view model (oracle `mobile/app/gate-rationale.tsx`).
///
/// Two modes, exactly as the oracle's `?date=` branch: with no `date` this is the live rationale
/// (gate + morning + recovery, the rich triggered-rules/suggestions/decision-trail screen); with a
/// `date` it is the deep-link target, which reads the far simpler per-date
/// `GET /api/v1/planning/morning-verdict` and deliberately shows less, because that row only ever
/// persists `{verdict, reason, session_prescription, computed_at}`.
///
/// The oracle's live branch goes through `useGateDecision`, which swaps in a locally computed gate
/// whenever a gate-config override is active. That override store is L3's (`GateConfig`), not this
/// lane's, so this reads the server gate straight — the swap is a one-line substitution at the
/// `gate` assignment when L3's store lands.
@Observable @MainActor
public final class GateRationaleViewModel {
    public enum Phase: Equatable, Sendable {
        case idle, loading, loaded
        case error(String)
        /// The ONE expected/benign failure of the by-date branch: no `morning_go.py` run ever
        /// happened for that date. Carries no Retry — there is nothing to retry.
        case noVerdictForDate(String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var gate: GateResponse?
    public private(set) var morning: MorningResponse?
    public private(set) var recovery: [RecoveryDay] = []
    public private(set) var verdictForDate: MorningVerdict?
    /// r4: the persisted verdict rows for the last 3 days, keyed by date (only rows whose own
    /// `date` matches the one asked for — never a neighbouring day's row passed off as this one).
    public private(set) var recentVerdicts: [String: MorningVerdict] = [:]
    public private(set) var lastError: HubError?

    /// W8-L4: DESIGN-7 `ScreenState`, resolved from `phase`/`lastError`. `.noVerdictForDate`
    /// (the hub answered; that day simply has no run) maps to `.empty` — an honest blank, not an
    /// error and not "never synced"; the view keeps reading `phase` for the per-date copy.
    public var screenState: ScreenState {
        ScreenState.resolve(phase: mappedPhase, neverSynced: false, verdictDate: nil, todayDateString: "", lastError: lastError)
    }

    private var mappedPhase: TodayViewModel.Phase {
        switch phase {
        case .idle: .idle
        case .loading: .loading
        case .loaded: .loaded
        case .noVerdictForDate: .empty
        case .error(let message): .error(message)
        }
    }

    private let provider: any HealthDataProvider
    /// `nil` = the live "today" rationale; non-nil = the deep-link per-date branch.
    public let date: String?
    private let windowDays: Int

    public init(provider: any HealthDataProvider, date: String? = nil, windowDays: Int = 28) {
        self.provider = provider
        self.date = date
        self.windowDays = windowDays
    }

    public var isByDate: Bool { date != nil }

    public func load() async {
        phase = .loading
        await refresh()
    }

    public func refresh() async {
        if let date { await loadByDate(date) } else { await loadLive() }
    }

    private func loadLive() async {
        do {
            async let g = provider.gate(windowDays: windowDays)
            async let m = provider.morning()
            async let r = provider.recovery(windowDays: windowDays)
            let (gateValue, morningValue, recoveryValue) = try await (g, m, r)
            gate = gateValue
            morning = morningValue
            recovery = recoveryValue
            recentVerdicts = await Self.fetchVerdicts(Self.lastThreeDates(anchor: morningValue.verdictDate), provider: provider)
            lastError = nil
            phase = .loaded
        } catch {
            let hubError = Self.asHubError(error)
            lastError = hubError
            // A screen that already holds a rationale keeps showing it rather than collapsing to an
            // error card (the same branching as TodayViewModel) — blank is not honest when
            // we hold real data.
            phase = gate == nil ? .error(Self.describe(hubError)) : .loaded
        }
    }

    private func loadByDate(_ date: String) async {
        do {
            verdictForDate = try await provider.morningVerdict(date: date)
            lastError = nil
            phase = .loaded
        } catch {
            let hubError = Self.asHubError(error)
            lastError = hubError
            if Self.isNotFound(hubError) {
                phase = .noVerdictForDate("No readiness verdict was computed for \(date).")
            } else {
                phase = verdictForDate == nil ? .error(Self.describe(hubError)) : .loaded
            }
        }
    }

    /// Each date's persisted row, fetched concurrently; a failed or mismatched row is simply absent.
    private static func fetchVerdicts(_ dates: [String], provider: any HealthDataProvider) async -> [String: MorningVerdict] {
        await withTaskGroup(of: MorningVerdict?.self) { group in
            for date in dates {
                group.addTask { (try? await provider.morningVerdict(date: date)).flatMap { $0.date == date ? $0 : nil } }
            }
            var out: [String: MorningVerdict] = [:]
            for await row in group { if let row { out[row.date] = row } }
            return out
        }
    }

    private static var isoCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private nonisolated static func parseDay(_ date: String, _ calendar: Calendar) -> Date? {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The verdict day and the two before it, newest first ("2026-09-01" -> 09-01, 08-31, 08-30).
    nonisolated static func lastThreeDates(anchor: String?) -> [String] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let anchor, let day = parseDay(anchor, calendar) else { return [] }
        return (0..<3).compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: day).map {
                let c = calendar.dateComponents([.year, .month, .day], from: $0)
                return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            }
        }
    }

    /// Oracle: a real `.status === 404`, or the mock provider's stand-in plain error whose message
    /// says so. Every other failure (network, 401, …) gets the generic message + Retry.
    private static func isNotFound(_ error: HubError) -> Bool {
        switch error {
        case .http(let status, _): return status == 404
        case .decoding(let detail): return detail.range(of: "no morning verdict", options: .caseInsensitive) != nil
        default: return false
        }
    }

    // MARK: - Derived (pure)

    /// The readiness verdict word/session/tone. In by-date mode this is the persisted row's verdict.
    /// W-FIX1 BUG-03: the hub's auto-regulated GO reads amber (Modified), not a green Full.
    public var verdict: VerdictParts {
        displayVerdictParts(verdictParts(isByDate ? verdictForDate?.verdict : morning?.verdict))
    }

    /// The persisted `/morning-verdict` reason behind `verdict` (by date: that row; live: the
    /// verdict day's row from `recentVerdicts`), or nil.
    private var verdictReason: String? {
        if isByDate { return verdictForDate?.reason }
        return morning?.verdictDate.flatMap { recentVerdicts[$0]?.reason }
    }

    /// W-FIX1 BUG-03: what the amber day trims ("Lift at current weights 1-2 reps shy of failure;
    /// trim Z2 to ~25min or walk."), nil on any other verdict.
    public var verdictPrescription: String? { autoRegulatedPrescription(verdict, reason: verdictReason) }

    /// W-FIX1 BUG-03: why the hub trimmed the day ("overnight vitals not synced yet"), nil when the
    /// persisted row carries no amber clause.
    public var verdictWhy: String? { autoRegulatedWhy(verdict, reason: verdictReason) }

    /// B-57 W1 r5: the header's word as Decide says it ("Full" / "Modified" / "Rest").
    public var verdictWord: String { verdictUserWord(verdict) }

    /// `computed_at` ("2026-09-03T05:10:43.887829+02:00") -> "05:10", or nil when unparsable.
    public func computedAtTime(locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String? {
        guard let raw = verdictForDate?.computedAt, let date = Self.parseISO(raw) else { return nil }
        var style = Date.FormatStyle(locale: locale, timeZone: timeZone)
        style = style.hour(.twoDigits(amPM: .abbreviated)).minute(.twoDigits)
        return date.formatted(style)
    }

    /// HT writes `computed_at` with fractional seconds and an offset ("…:43.887829+02:00"); older
    /// rows may carry neither, so both shapes are tried rather than returning nil on the variant.
    static func parseISO(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: raw) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    public var recommendationLabel: String? {
        gate.map { GateInsight.recommendationLabel($0.recommendation) }
    }

    /// The honest counts, shown only for INSUFFICIENT_DATA (oracle) — never under the verdict word.
    public var trackedDaysLine: String? {
        guard let gate, gate.recommendation == .insufficientData else { return nil }
        return GateInsight.trackedDaysLine(gate)
    }

    /// Humanized rules — never the raw `"metric value vs threshold X (RULE: reason)"` debug string.
    public func humanizedRules(locale: Locale = .autoupdatingCurrent) -> [String] {
        (gate?.triggeredRules ?? []).map { GateHumanizeRule.humanize($0, locale: locale) }
    }

    /// The Suggestions section's bullets. When the gate supplied none but a rule fired, the derived
    /// action stands in — "No specific suggestions right now." must never sit under a triggered rule.
    public var suggestionLines: [String] {
        guard let gate else { return [] }
        if !gate.suggestions.isEmpty { return gate.suggestions }
        guard !gate.triggeredRules.isEmpty else { return [] }
        // The action fragments are written to follow an em dash ("… — front-load protein …"), i.e.
        // lowercase start; as a standalone bullet it reads as its own sentence.
        return [GateHumanizeRule.capitalizeFirst(GateInsight.actionForTriggeredRules(gate)) + "."]
    }

    /// Shown only when there is genuinely nothing to suggest AND nothing triggered.
    public var suggestionsEmptyCopy: String? {
        suggestionLines.isEmpty ? "No specific suggestions right now." : nil
    }

    public var noRulesCopy: String? {
        (gate?.triggeredRules.isEmpty ?? true) ? "No rules triggered — a clean day against every threshold." : nil
    }

    /// Board "Weekly nutrition": the 7-day energy balance, or nil. B-73 / W-FIX1 BUG-07: balance =
    /// intake − expenditure (resting + active), both from one source, averaged over 7 days — the
    /// hub's ONE definition (`avg_kcal_deficit_7d` = expenditure − intake), so the balance is its
    /// negation. Never the gap to a kcal goal. See `weeklyEnergyBalance`.
    public var energyBalance7d: Double? { gate.flatMap { weeklyEnergyBalance($0.averages) } }
    /// Board "Weekly nutrition": the 7-day average protein, or nil.
    public var protein7d: Double? { gate?.averages.avgProtein7d }

    /// The caption under the weekly tiles: the weekly gate's own recommendation, its honest counts,
    /// the humanized triggered rules and the suggestions — what the removed "Weekly nutrition gate",
    /// "Why — triggered rules" and "Suggestions" cards used to say, now in the board's caption slot.
    ///
    /// W-FIX1 BUG-27: ONE plain sentence, never the hub's raw lines ("Gate recommends REDUCE",
    /// "7-day intake averages 1'456 kcal against the 1'600 kcal floor…"): "This week (<why>):
    /// <what to do>." when a rule fired or the gate suggested something, else the recommendation in
    /// words; INSUFFICIENT_DATA carries its honest counts.
    public func weeklyNotes(locale: Locale = .autoupdatingCurrent) -> [String] {
        guard let gate else { return [] }
        if gate.recommendation == .insufficientData {
            return ["Not enough tracked days this week for a nutrition call (\(GateInsight.trackedDaysLine(gate)))."]
        }
        guard !gate.triggeredRules.isEmpty || !gate.suggestions.isEmpty else {
            return [weeklyGatePlainSentence(gate.recommendation)]
        }
        let reason = gate.triggeredRules.first.flatMap { GateInsight.parseTriggeredRule($0).reason }.flatMap { $0.isEmpty ? nil : $0 }
        var action = GateInsight.actionForTriggeredRules(gate).trimmingCharacters(in: .whitespaces)
        if let first = action.first { action = first.lowercased() + action.dropFirst() }
        if !action.hasSuffix(".") { action += "." }
        return [reason.map { "This week (\($0)): \(action)" } ?? "This week: \(action)"]
    }

    /// Board "Last 3 days": newest first, from the verdict day back.
    public func lastDays(locale: Locale = .autoupdatingCurrent) -> [GateDayRow] {
        let calendar = Self.isoCalendar
        return Self.lastThreeDates(anchor: morning?.verdictDate).map { date in
            // "Wed 23" (the board's form), composed so no locale reorders it into "23, Wed".
            let label = Self.parseDay(date, calendar).map { d in
                let weekday = d.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated))
                return "\(weekday) \(calendar.component(.day, from: d))"
            } ?? date
            guard let row = recentVerdicts[date] else {
                return GateDayRow(date: date, dayLabel: label, session: nil, verdictWord: nil, tone: .muted)
            }
            let parts = displayVerdictParts(verdictParts(row.verdict))
            let session = row.sessionPrescription.flatMap { $0.isEmpty ? nil : $0 } ?? (parts.session.isEmpty ? nil : parts.session)
            return GateDayRow(date: date, dayLabel: label, session: session, verdictWord: verdictUserWord(parts), tone: parts.tone,
                              prescription: autoRegulatedPrescription(parts, reason: row.reason))
        }
    }

    /// The 3 most recent recovery days, oldest-first for left-to-right reading order (recovery
    /// arrives newest-first). W-FIX1 BUG-06: HRV is each night's own RMSSD
    /// (`KpiMetrics.nightlyHrvMs`), never the morning series' 7-day `hrv_weekly_avg` mix; the
    /// field keeps its W-B57 name.
    public var trailDays: [GateTrailDay] {
        recovery.prefix(3).reversed().map { day in
            GateTrailDay(
                date: day.date,
                hrvWeeklyAvg: KpiMetrics.nightlyHrvMs(day),
                rhrBpm: day.rhrBpm,
                sleepScore: day.sleepScore,
                tone: Self.readinessTone(day.readinessScore)
            )
        }
    }

    /// Garmin's own 0–100 daily `readiness_score`, bucketed ONLY to colour the trail dot — not a
    /// reproduction of the HRV/sleep gate rules.
    static func readinessTone(_ score: Double?) -> VerdictTone {
        guard let score else { return .muted }
        if score >= 70 { return .go }
        if score >= 40 { return .amber }
        return .red
    }

    private static func asHubError(_ error: Error) -> HubError { (error as? HubError) ?? .decoding("\(error)") }

    private static func describe(_ error: HubError) -> String {
        switch error {
        case .unauthorized: "Hub rejected the token — check Settings › Connection."
        case .network: "Hub unreachable — is the Mac awake and on the same network?"
        default: "Couldn't load the readiness rationale."
        }
    }
}

// MARK: - B-33 §8.5 fixture

public extension GateRationaleViewModel {
    /// A loaded rationale for `ScreenRegistry`/the screenshot sweep, built from wire-format
    /// literals (the DTOs' memberwise inits are internal). Never used by the app.
    static func fixture() -> GateRationaleViewModel {
        let model = GateRationaleViewModel(provider: MockDataProvider())
        model.gate = NativeFixtureStore.decode(fixtureGateJSON, as: GateResponse.self)
        // Today's shared gate fixture carries no deficit; the rationale's Energy tile needs one.
        model.gate?.averages.avgKcalDeficit7d = 598
        model.morning = NativeFixtureStore.decode(fixtureRationaleMorningJSON, as: MorningResponse.self)
        model.recovery = (0..<3).map { i in
            RecoveryDay(
                date: "2026-09-\(19 + i)",
                sleepScore: [83, 79, 85][i],
                rhrBpm: [53, 54, 52][i],
                readinessScore: [74, 70, 76][i],
                hrvWeeklyAvg: [51, 49, 52][i]
            )
        }
        // 2026-09-19 deliberately absent: the table's "—" + No data row.
        for (date, verdict, session) in [("2026-09-21", "GO — full session", "Day 2 Full Upper"),
                                         ("2026-09-20", "REDUCED — easy Z2", "Intervals swapped for easy Z2")] {
            model.recentVerdicts[date] = NativeFixtureStore.decode(
                #"{"date":"\#(date)","verdict":"\#(verdict)","session_prescription":"\#(session)","computed_at":"\#(date)T07:41:00+02:00"}"#,
                as: MorningVerdict.self)
        }
        model.phase = .loaded
        return model
    }
}

private let fixtureRationaleMorningJSON = """
{"today_activities":[],"verdict":"GO — full session","verdict_date":"2026-09-21","carb_watch_floor":180,"hrv_series":[],
 "gate_signals":[
  {"key":"sleep","label":"Sleep","value":85,"unit":"","threshold":70,"direction":"min","scale_min":0,"scale_max":100,"status":"pass","note":null},
  {"key":"hrv","label":"HRV","value":52,"unit":"ms","threshold":27,"direction":"min","scale_min":0,"scale_max":80,"status":"pass","note":null},
  {"key":"rhr","label":"RHR","value":52,"unit":"bpm","threshold":65,"direction":"max","scale_min":40,"scale_max":80,"status":"pass","note":null},
  {"key":"sleep_h","label":"Sleep time","value":null,"unit":"h","threshold":6.0,"direction":"min","scale_min":0,"scale_max":10,"status":"missing","note":null}]}
"""

/// B-73 / W-FIX1 BUG-07: the 7-day energy balance (intake − expenditure) from the hub's single
/// definition — `avg_kcal_deficit_7d` is expenditure − intake over the same 7 days — or nil.
public nonisolated func weeklyEnergyBalance(_ averages: GateAverages) -> Double? {
    averages.avgKcalDeficit7d.map { -$0 }
}
