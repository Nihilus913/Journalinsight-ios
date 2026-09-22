import SwiftUI
import JICore
import JIDesign

/// Recovery screen (W2b-L2, frozen contract `RecoveryView.init(model:)`). Composes the W2a
/// primitives: `ReadinessArcGauge` + `SleepCard` + `SleepScoreComponents` + `ContributorBreakdown`,
/// plus a Swift Charts trend over the `[RecoveryDay]` series. Rule 5 (never render a zero for
/// missing data) and rule 6 (green reserved for the 0–100 readiness/sleep score; trend marks
/// neutral `mutedNested`) both apply throughout.
public struct RecoveryView: View {
    @Bindable private var model: RecoveryViewModel
    @Environment(\.jiTheme) private var theme
    /// B-33 §8.5: no hub fetch while the sweep renders this screen.
    @Environment(\.jiOffscreenRender) private var offscreen
    @State private var trendRange: TrendRange = .week

    public init(model: RecoveryViewModel) { self.model = model }

    public var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .empty: Surface { Text("No data yet — run a sync on the hub.").foregroundStyle(theme.color(.muted)) }
                    .accessibilityLabel("No data yet — run a sync on the hub.")
                case .loaded: loaded
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .background(theme.color(.bg))
        // §5: the hand-drawn large title becomes the system one; the date line is the subtitle.
        .navigationTitle("Recovery")
        .navigationSubtitle(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .refreshable { await model.refresh() }
        // CODE-1: gate on `hasLiveResult`, not `phase == .idle` — mirrors `TodayView.task`.
        .task { if !offscreen, !model.hasLiveResult { await model.load() } }
        .animation(JIMotion.standard, value: model.phase)
    }

    private var loading: some View {
        Surface(level: 1, padding: 20) {
            VStack(alignment: .leading, spacing: 12) { SkeletonBlock(width: 160, height: 160); SkeletonBlock(width: 240); SkeletonBlock(height: 90) }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg).foregroundStyle(theme.color(.text))
                    .accessibilityLabel(msg)
                Button("Retry") { Task { await model.refresh() } }.buttonStyle(.pressableScale).tint(theme.color(.info))
                    .accessibilityLabel("Retry")
                    .accessibilityIdentifier("recovery.retry")
            }
        }
    }

    private var loaded: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let staleDate = staleVerdictBanner {
                Surface(level: 2) {
                    Text("Showing recovery from \(staleDate) — no newer sync yet.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .accessibilityLabel("Showing recovery from \(staleDate) — no newer sync yet.")
                }
            }
            // §8.1: hero + its one small ring compose side by side in regular width, stack in compact.
            // §4b: Recovery = hero arc + Sleep ring only — never HRV / RHR / ACWR.
            AdaptiveHStack {
                Surface(level: 1, padding: 20) {
                    HStack {
                        Spacer()
                        // RN oracle `ReadinessArcGauge.tsx`: `Readiness ${rounded} — open detail`, else
                        // `Readiness — open detail` when there is no score.
                        ReadinessArcGauge(score: model.latestReadiness)
                            .accessibilityLabel(model.latestReadiness.map { "Readiness \(Int($0.rounded())) — open detail" } ?? "Readiness — open detail")
                            .accessibilityIdentifier("recovery.readinessGauge")
                        Spacer()
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    sleepRing
                    SleepCard(durationSec: model.latestSleepDurationSec, score: model.latestSleepScore)
                        .accessibilityLabel("Sleep — open detail")
                        .accessibilityIdentifier("recovery.sleepCard")
                }
            }
            section("Sleep components") {
                SleepScoreComponents(components: sleepComponents)
                    .accessibilityIdentifier("recovery.sleepComponents")
            }
            section("Readiness drivers") {
                ContributorBreakdown(contributors: contributors)
                    .accessibilityIdentifier("recovery.readinessDrivers")
            }
            section("Trend") { trendChart }
        }
    }

    /// §2/§2b: an uppercase section header above the card, not a caption inside it.
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            JISectionHeader(title)
            Surface(level: 1) { content().frame(maxWidth: .infinity, alignment: .leading) }
        }
    }

    /// §4b: Sleep score 0–100, purple, 44 pt. Rule 5 — no ring value without a score.
    @ViewBuilder
    private var sleepRing: some View {
        Surface(level: 1) {
            HStack(spacing: 12) {
                ScoreRing(value: model.latestSleepScore ?? 0, max: 100, tint: model.latestSleepScore == nil ? theme.color(.nested) : theme.color(.sleep))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sleep score").jiFont(.caption).foregroundStyle(theme.color(.muted))
                    Text(model.latestSleepScore.map { "\(Int($0.rounded()))" } ?? "No data yet")
                        .jiFont(.subheadline, weight: .semibold)
                        .foregroundStyle(model.latestSleepScore == nil ? theme.color(.muted) : theme.color(.text))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.latestSleepScore.map { "Sleep score \(Int($0.rounded())) of 100" } ?? "Sleep score, no data yet")
        .accessibilityIdentifier("recovery.sleepRing")
    }

    private var staleVerdictBanner: String? {
        if case .staleVerdictDate(let date) = model.screenState { return date }
        return nil
    }

    private var sleepComponents: [SleepScoreComponent] {
        let sorted = model.days.sorted { $0.date > $1.date }
        let latest = sorted.first
        return [
            SleepScoreComponent(id: "duration", label: "Duration", value: latest?.sleepDurationSec.map { $0 / 60 }),
            SleepScoreComponent(id: "bodyBattery", label: "Body battery", value: latest?.bodyBatteryAvg),
        ]
    }

    private var contributors: [ReadinessContributor] {
        let sorted = model.days.sorted { $0.date > $1.date }
        let latest = sorted.first
        return [
            ReadinessContributor(id: "hrv", label: "HRV", value: latest?.hrvWeeklyAvg, magnitude: latest?.hrvWeeklyAvg ?? 0),
            ReadinessContributor(id: "rhr", label: "RHR", value: latest?.rhrBpm, magnitude: latest?.rhrBpm ?? 0),
            ReadinessContributor(id: "acwr", label: "ACWR", value: latest?.acwr, magnitude: (latest?.acwr ?? 0) * 100),
        ]
    }

    /// §2b.3: the Health range picker + Swift Charts axis style come from JIDesign now; the
    /// readiness series is the one bounded 0–100 metric this screen trends.
    private var trendChart: some View {
        TrendChart(
            points: model.days.sorted { $0.date < $1.date }.compactMap { day in
                day.readinessScore.flatMap { score in
                    recoveryTrendDate(day.date).map { TrendPoint(date: $0, value: score) }
                }
            },
            tint: theme.color(.go),
            unit: "score",
            range: $trendRange,
            showAll: nil
        )
        .accessibilityLabel("Readiness trend")
        .accessibilityIdentifier("recovery.trendChart")
    }
}

/// The hub's `YYYY-MM-DD` day string as a chart x-value. UTC on purpose — a day string has no
/// time zone, and `TrendChart` only ever orders and labels these.
public nonisolated func recoveryTrendDate(_ day: String, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
    var c = calendar
    c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let parts = day.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return c.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
}
