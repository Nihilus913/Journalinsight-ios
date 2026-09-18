import SwiftUI
import JICore
import JIDesign

/// The gate's own reasoning (triggered rules + suggestions) plus the 3-day decision trail — the
/// oracle's `mobile/app/gate-rationale.tsx`, reached by tapping the verdict hero on Today
/// (`VerdictHero.tsx:404` → `router.push("/gate-rationale")`).
///
/// Two branches, exactly as the oracle: the live rationale, and the deep-link per-date branch which
/// deliberately shows less (the persisted `morning_verdict` row has no rules/suggestions/trail).
public struct GateRationaleView: View {
    @Bindable var model: GateRationaleViewModel

    public init(model: GateRationaleViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch model.phase {
                case .idle, .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .noVerdictForDate(let copy):
                    // The ONE benign failure — nothing to retry, so no Retry button (oracle).
                    Surface {
                        Text(copy).font(.footnote).foregroundStyle(JIColor.muted)
                            .accessibilityIdentifier("gateRationale.noVerdict")
                    }
                case .error(let message):
                    errorCard(message)
                case .loaded:
                    verdictCard
                    if model.isByDate {
                        byDateReasonCard
                    } else {
                        nutritionGateCard
                        triggeredRulesCard
                        contributorsCard
                        suggestionsCard
                        decisionTrailCard
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(JIColor.bg)
        .navigationTitle("Readiness rationale")
        .task { await model.load() }
    }

    // MARK: - Cards

    private func errorCard(_ message: String) -> some View {
        Surface {
            VStack(spacing: 10) {
                Text(message).font(.footnote).foregroundStyle(JIColor.muted)
                Button("Retry") { Task { await model.refresh() } }
                    .buttonStyle(.pressableScale)
                    .accessibilityLabel("Retry loading the readiness rationale")
                    .accessibilityIdentifier("gateRationale.retry")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var verdictCard: some View {
        Surface(radius: JIRadius.hero, padding: 20) {
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("Readiness verdict")
                Text(model.verdict.word)
                    .jiNumeral(.numeralLarge, weight: .heavy)
                    .foregroundStyle(JIColor.color(for: model.verdict.tone))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .accessibilityIdentifier("gateRationale.verdict.word")
                if !model.verdict.session.isEmpty {
                    Text(model.verdict.session).font(.footnote).foregroundStyle(JIColor.muted)
                        .accessibilityIdentifier("gateRationale.verdict.session")
                }
                if let time = model.computedAtTime() {
                    Text("Computed \(time)").font(.caption2).foregroundStyle(JIColor.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var byDateReasonCard: some View {
        if let reason = model.verdictForDate?.reason, !reason.isEmpty {
            card("Why") {
                Text(reason).font(.footnote).foregroundStyle(JIColor.text)
                    .accessibilityIdentifier("gateRationale.byDate.reason")
            }
        }
    }

    /// 2026-09-08 fix (oracle): `recommendation` is the WEEKLY NUTRITION KPI gate's verdict, not the
    /// morning readiness verdict — its own card, with the honest counts.
    private var nutritionGateCard: some View {
        card("Weekly nutrition gate") {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.recommendationLabel ?? "—").font(.footnote).foregroundStyle(JIColor.text)
                    .accessibilityIdentifier("gateRationale.recommendation")
                if let tracked = model.trackedDaysLine {
                    Text(tracked).font(.caption).foregroundStyle(JIColor.muted)
                        .accessibilityIdentifier("gateRationale.trackedDays")
                }
            }
        }
    }

    private var triggeredRulesCard: some View {
        card("Why — triggered rules") {
            if let clean = model.noRulesCopy {
                Text(clean).font(.caption).foregroundStyle(JIColor.muted)
                    .accessibilityIdentifier("gateRationale.noRules")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(model.humanizedRules().enumerated()), id: \.offset) { _, rule in
                        bullet(rule, dot: JIColor.reduced)
                    }
                }
                .accessibilityIdentifier("gateRationale.triggeredRules")
            }
        }
    }

    /// The numeric WHY alongside the qualitative rules — the gate's own 7-day averages, ranked by
    /// magnitude. Neutral bars only (green is reserved for verdict/band/score).
    private var contributorsCard: some View {
        card("Contributors") {
            ContributorBreakdown(contributors: contributors)
                .accessibilityIdentifier("gateRationale.contributors")
        }
    }

    private var contributors: [ReadinessContributor] {
        let a = model.gate?.averages
        return [
            ReadinessContributor(id: "kcal", label: "7d kcal", value: a?.avgKcal7d, magnitude: a?.avgKcal7d ?? 0),
            ReadinessContributor(id: "protein", label: "7d protein", value: a?.avgProtein7d, magnitude: (a?.avgProtein7d ?? 0) * 10),
            ReadinessContributor(id: "sleep", label: "7d sleep score", value: a?.sleepScore7d, magnitude: (a?.sleepScore7d ?? 0) * 10),
            // ACWR lives on a 0–2 scale; scaled so it is comparable against the others' magnitudes
            // rather than always ranking last (RecoveryView's ContributorBreakdown does the same).
            ReadinessContributor(id: "acwr", label: "ACWR", value: a?.acwr, magnitude: (a?.acwr ?? 0) * 1000),
        ]
    }

    private var suggestionsCard: some View {
        card("Suggestions") {
            if let empty = model.suggestionsEmptyCopy {
                Text(empty).font(.caption).foregroundStyle(JIColor.muted)
                    .accessibilityIdentifier("gateRationale.noSuggestions")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(model.suggestionLines.enumerated()), id: \.offset) { _, line in
                        bullet(line, dot: JIColor.go)
                    }
                }
                .accessibilityIdentifier("gateRationale.suggestions")
            }
        }
    }

    private var decisionTrailCard: some View {
        let days = model.trailDays
        return card("Decision trail · last \(days.count) days") {
            if days.isEmpty {
                Text("No recovery history yet.").font(.caption).foregroundStyle(JIColor.muted)
                    .accessibilityIdentifier("gateRationale.noTrail")
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(days) { day in
                        VStack(spacing: 4) {
                            Circle().fill(JIColor.color(for: day.tone)).frame(width: 12, height: 12)
                            Text(Self.weekdayLabel(day.date)).font(.caption2.weight(.bold)).foregroundStyle(JIColor.text)
                            Text(day.metricsLine()).jiFont(.micro).foregroundStyle(JIColor.muted)
                                .multilineTextAlignment(.center).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(day.date): \(day.metricsLine())")
                    }
                }
                .accessibilityIdentifier("gateRationale.decisionTrail")
            }
        }
    }

    // MARK: - Primitives

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        Surface(level: 2, padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel(title)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .kerning(0.8)
            .foregroundStyle(JIColor.muted)
            .accessibilityAddTraits(.isHeader)
    }

    private func bullet(_ text: String, dot: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").font(.footnote).foregroundStyle(dot)
            Text(text).font(.footnote).foregroundStyle(JIColor.text).frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    /// "2026-09-11" -> "Thu". Parsed as a plain calendar date (no timezone shift off the hub's day).
    nonisolated static func weekdayLabel(_ date: String, locale: Locale = .autoupdatingCurrent) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let d = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return date }
        return d.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated))
    }
}

// MARK: - Entry point

extension EnvironmentValues {
    /// Set by the app's Today wiring; `nil` leaves the verdict hero inert (the same optional-model
    /// idiom as `VerdictHeroView.challengesModel`, routed through the environment so the entry site
    /// costs exactly one line and cannot collide with the other lane editing that file).
    @Entry public var gateRationaleModel: GateRationaleViewModel?
}

/// Makes the whole verdict hero the tap target into the rationale — the oracle's `VerdictCard`
/// `onPress` covers the entire card, with `accessibilityLabel="Readiness verdict details"`.
struct GateRationaleDestination: ViewModifier {
    @Environment(\.gateRationaleModel) private var model
    @State private var showRationale = false

    func body(content: Content) -> some View {
        if let model {
            Button { showRationale = true } label: { content }
                .buttonStyle(.pressableScale)
                .accessibilityLabel("Readiness verdict details")
                .accessibilityIdentifier("today.verdict.rationale")
                // Attached locally so this never needs the enclosing NavigationStack's own
                // `navigationDestination(for:)` — same rationale as the challenges link above it.
                .navigationDestination(isPresented: $showRationale) { GateRationaleView(model: model) }
        } else {
            content
        }
    }
}

extension View {
    /// One-line entry site for `VerdictHeroView` (oracle `VerdictHero.tsx:404`).
    func gateRationaleDestination() -> some View { modifier(GateRationaleDestination()) }
}
