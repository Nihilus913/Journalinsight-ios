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
            lastError = nil
            phase = .loaded
        } catch {
            let hubError = Self.asHubError(error)
            lastError = hubError
            // A screen that already holds a rationale keeps showing it rather than collapsing to an
            // error card (TodayViewModel/ChallengesViewModel branching) — blank is not honest when
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
    public var verdict: VerdictParts {
        verdictParts(isByDate ? verdictForDate?.verdict : morning?.verdict)
    }

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

    /// The 3 most recent recovery days, oldest-first for left-to-right reading order, joined to the
    /// morning HRV series by date (recovery arrives newest-first).
    public var trailDays: [GateTrailDay] {
        let hrvByDate = Dictionary(
            (morning?.hrvSeries ?? []).map { ($0.date, $0.hrvWeeklyAvg) },
            uniquingKeysWith: { _, last in last }
        )
        return recovery.prefix(3).reversed().map { day in
            GateTrailDay(
                date: day.date,
                hrvWeeklyAvg: hrvByDate[day.date] ?? nil,
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
        model.phase = .loaded
        return model
    }
}

private let fixtureRationaleMorningJSON = """
{"today_activities":[],"verdict":"GO — full session","verdict_date":"2026-09-21","carb_watch_floor":180,"hrv_series":[]}
"""
