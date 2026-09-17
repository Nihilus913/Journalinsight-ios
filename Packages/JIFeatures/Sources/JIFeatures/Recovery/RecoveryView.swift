import SwiftUI
import Charts
import JICore
import JIDesign

/// Recovery screen (W2b-L2, frozen contract `RecoveryView.init(model:)`). Composes the W2a
/// primitives: `ReadinessArcGauge` + `SleepCard` + `SleepScoreComponents` + `ContributorBreakdown`,
/// plus a Swift Charts trend over the `[RecoveryDay]` series. Rule 5 (never render a zero for
/// missing data) and rule 6 (green reserved for the 0–100 readiness/sleep score; trend marks
/// neutral `mutedNested`) both apply throughout.
public struct RecoveryView: View {
    @Bindable private var model: RecoveryViewModel

    public init(model: RecoveryViewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .empty: Surface { Text("No data yet — run a sync on the hub.").foregroundStyle(JIColor.muted) }
                case .loaded: loaded
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
        }
        .background(JIColor.bg)
        .refreshable { await model.refresh() }
        // CODE-1: gate on `hasLiveResult`, not `phase == .idle` — mirrors `TodayView.task`.
        .task { if !model.hasLiveResult { await model.load() } }
        .animation(JIMotion.standard, value: model.phase)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recovery").font(.largeTitle.bold()).foregroundStyle(JIColor.text)
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.subheadline).foregroundStyle(JIColor.muted)
        }
    }

    private var loading: some View {
        Surface(level: 1, radius: JIRadius.hero, padding: 20) {
            VStack(alignment: .leading, spacing: 12) { SkeletonBlock(width: 160, height: 160); SkeletonBlock(width: 240); SkeletonBlock(height: 90) }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg).foregroundStyle(JIColor.text)
                Button("Retry") { Task { await model.refresh() } }.buttonStyle(.pressableScale).tint(JIColor.info)
            }
        }
    }

    private var loaded: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let staleDate = staleVerdictBanner {
                Surface(level: 2) {
                    Text("Showing recovery from \(staleDate) — no newer sync yet.").font(.footnote).foregroundStyle(JIColor.muted)
                }
            }
            HStack {
                Spacer()
                ReadinessArcGauge(score: model.latestReadiness)
                Spacer()
            }
            SleepCard(durationSec: model.latestSleepDurationSec, score: model.latestSleepScore)
            Surface(level: 2) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sleep components").font(.caption).foregroundStyle(JIColor.muted)
                    SleepScoreComponents(components: sleepComponents)
                }
            }
            Surface(level: 2) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Readiness drivers").font(.caption).foregroundStyle(JIColor.muted)
                    ContributorBreakdown(contributors: contributors)
                }
            }
            Surface(level: 2) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Trend").font(.caption).foregroundStyle(JIColor.muted)
                    trendChart
                }
            }
        }
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

    @ViewBuilder
    private var trendChart: some View {
        let points = model.days.sorted { $0.date < $1.date }
        if points.isEmpty {
            Text("No data yet").font(.caption).foregroundStyle(JIColor.muted)
        } else {
            Chart {
                ForEach(points, id: \.date) { day in
                    if let readiness = day.readinessScore {
                        LineMark(x: .value("Date", day.date), y: .value("Readiness", readiness))
                            .foregroundStyle(JIColor.mutedNested)
                            .symbol(.circle)
                    }
                    if let sleep = day.sleepScore {
                        LineMark(x: .value("Date", day.date), y: .value("Sleep", sleep))
                            .foregroundStyle(JIColor.sleep)
                            .symbol(.square)
                    }
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 140)
        }
    }
}
