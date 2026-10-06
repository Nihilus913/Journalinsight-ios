import Charts
import Foundation
import JICore
import JIDesign
import Observation
import SwiftUI

// MARK: - W-B98A B98-4 (B-98 5a, Bevel BP-5): Activity detail — km splits + HR/pace chart
//
// Tap a completed workout on Training › This day → this screen. The hub computes the km splits
// and ≤ 300 HR/pace points from the stored 1 s samples (`GET /training/activity/{id}/series`);
// a GPS-less Apple run shows HR only. Display only — it never marks an interval done.

/// The tap entry: set by Training on its day card, read by `CompletedWorkoutRow` (nil = the row
/// is not tappable, e.g. on Today).
public extension EnvironmentValues {
    @Entry var openActivityDetail: (@MainActor (DayActivity) -> Void)? = nil
}

/// "14:01" (min:s per km) from seconds per km; nil for a missing / non-finite pace (rule 5).
public nonisolated func activityPaceText(_ secondsPerKm: Double?) -> String? {
    guard let s = secondsPerKm, s.isFinite, s > 0 else { return nil }
    let whole = Int(s.rounded())
    return "\(whole / 60):\(String(format: "%02d", whole % 60))"
}

/// One row of the split table, already in display text.
public nonisolated struct ActivitySplitRow: Equatable, Sendable, Identifiable {
    public let id: Int
    /// "1" … for whole km; "0.69 km" for the last partial km.
    public let label: String
    public let pace: String
    public let hr: String
    public let elevation: String
}

/// The split table rows. A missing value reads "–", never "0" (rule 5).
public nonisolated func activitySplitRows(_ s: ActivitySeries) -> [ActivitySplitRow] {
    s.splits.map { sp in
        let partial = sp.distanceM < 999.5
        let label = partial ? "\(jiNumber(sp.distanceM / 1000, 2)) km" : "\(sp.km)"
        let hr = sp.meanHr.flatMap { $0.isFinite && $0 > 0 ? "\(Int($0.rounded()))" : nil } ?? "–"
        let elev = sp.elevationGainM.flatMap { $0.isFinite ? "+\(Int($0.rounded()))" : nil } ?? "–"
        return ActivitySplitRow(id: sp.km, label: label, pace: activityPaceText(sp.paceSPerKm) ?? "–", hr: hr, elevation: elev)
    }
}

/// One chart point: minutes from the start; pace in minutes per km (the axis reads "min/km").
public nonisolated struct ActivityChartPoint: Equatable, Sendable, Identifiable {
    public let minute: Double
    public let hr: Double?
    public let pace: Double?
    public var id: Double { minute }
}

public nonisolated func activityChartPoints(_ s: ActivitySeries) -> [ActivityChartPoint] {
    s.points.map { p in
        ActivityChartPoint(minute: p.t / 60,
                           hr: p.hr.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
                           pace: p.paceSPerKm.flatMap { $0.isFinite && $0 > 0 ? $0 / 60 : nil })
    }
}

/// X-axis label: "25 min"; "0:30" (min:s) when the workout is under 10 min, so short runs never
/// repeat "0 min" / "1 min".
public nonisolated func activityAxisMinuteText(_ minute: Double, span: Double) -> String {
    guard span < 10 else { return "\(Int(minute.rounded())) min" }
    let s = Int((minute * 60).rounded())
    return "\(s / 60):\(String(format: "%02d", s % 60))"
}

/// The HR-only note (GPS-less, speed-less Apple runs); nil when the run has pace.
public nonisolated func activityHrOnlyNote(_ s: ActivitySeries) -> String? {
    s.hrOnly ? "HR only — this workout has no GPS or speed, so no pace or splits." : nil
}

/// What the user reads when the series fails — never a raw Swift error string.
nonisolated func activityDetailErrorText(_ error: any Error) -> String {
    let offline = "Can't reach the hub — check your connection and pull to retry."
    switch error {
    case HubError.unauthorized: return "The hub rejected the token — check Settings › Connection."
    case HubError.network: return offline
    case HubError.decoding: return "The hub sent data this app can't read — update the app or the hub."
    case HubError.http(let status, _): return "The hub couldn't build this workout's series (error \(status)). Try again later."
    case is URLError: return offline
    default: return "Something went wrong loading this workout. Pull to retry."
    }
}

@MainActor @Observable
public final class ActivityDetailModel {
    public enum Phase: Equatable { case loading, loaded(ActivitySeries), unavailable, error(String) }
    public private(set) var phase: Phase = .loading
    public private(set) var staleSince: Date?
    public let activity: DayActivity
    @ObservationIgnored private let provider: (any ActivitySeriesProviding)?

    public init(activity: DayActivity, provider: (any ActivitySeriesProviding)?) {
        self.activity = activity; self.provider = provider
    }

    /// The row's own title ("Morning run" / "Running").
    public var title: String { completedWorkoutRowText(activity).title }

    public func load() async {
        guard let provider else { phase = .unavailable; return }
        let id = activity.activityId
        do {
            let (series, since) = try await HubReadTrace.collect { try await provider.activitySeries(activityId: id) }
            phase = .loaded(series); staleSince = since
        } catch HubError.http(status: 404, _) {
            phase = .unavailable
        } catch {
            if case .loaded = phase { return }   // a failed refresh keeps what is shown
            phase = .error(activityDetailErrorText(error))
        }
    }

    public var offlineText: String? { staleSince.map { offlineReadCaption(since: $0) } }
}

/// Identity-hashed so `navigationDestination(item:)` can push one model instance.
extension ActivityDetailModel: Hashable {
    public nonisolated static func == (a: ActivityDetailModel, b: ActivityDetailModel) -> Bool { a === b }
    public nonisolated func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }
}

public struct ActivityDetailView: View {
    let model: ActivityDetailModel
    private let theme = JITheme.native
    public init(model: ActivityDetailModel) { self.model = model }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: JISpacing.s3) {
                    summary
                    content
                }
                .padding(.horizontal, JISpacing.s4).padding(.vertical, JISpacing.s3)
            }
            #if DEBUG
            // B-98 dev affordance: `-activity-scroll-splits` scrolls to the split table once loaded (sim shots).
            .onChange(of: model.phase) { _, phase in
                guard case .loaded = phase, CommandLine.arguments.contains("-activity-scroll-splits") else { return }
                Task { try? await Task.sleep(for: .milliseconds(500)); proxy.scrollTo("splits", anchor: .top) }
            }
            #endif
        }
        .background(theme.color(.bg).ignoresSafeArea())
        .navigationTitle(model.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task { await model.load() }
        .refreshable { await model.load() }
        .jiTheme(.native)
        .accessibilityIdentifier("activity-detail")
    }

    private var summary: some View {
        let text = completedWorkoutRowText(model.activity)
        return VStack(alignment: .leading, spacing: 2) {
            if let source = text.sourceLabel {
                Text(source).jiFont(.caption).foregroundStyle(theme.color(.muted))
            }
            if !text.metrics.isEmpty {
                Text(text.metrics.joined(separator: " · ")).jiFont(.subheadline, weight: .semibold)
                    .foregroundStyle(theme.color(.text))
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            Surface(level: 1) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(theme.color(.muted).opacity(0.12))
                    ProgressView()
                }
                .frame(height: 220)
            }
            .accessibilityLabel("Loading")
            .accessibilityIdentifier("activity-detail-loading")
        case .unavailable:
            note("No recorded series for this workout.", "Splits and the HR/pace chart need the hub's stored samples.")
                .accessibilityIdentifier("activity-detail-unavailable")
        case .error(let message):
            note("Couldn't load this workout.", message)
                .accessibilityIdentifier("activity-detail-error")
        case .loaded(let s):
            loaded(s)
        }
    }

    @ViewBuilder private func loaded(_ s: ActivitySeries) -> some View {
        if let offline = model.offlineText {
            Text(offline).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                .accessibilityIdentifier("activity-detail-offline")
        }
        let points = activityChartPoints(s)
        if let hrOnly = activityHrOnlyNote(s) {
            Text(hrOnly).jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("activity-detail-hr-only")
        }
        if points.contains(where: { $0.hr != nil }) {
            chartCard(title: "Heart rate", unit: "bpm", role: .rhr, id: "activity-detail-hr-chart",
                      values: points.compactMap { p in p.hr.map { (p.minute, $0) } }, reversed: false)
        } else {
            note("No heart rate recorded.", "This workout has no HR samples.")
        }
        if !s.hrOnly, points.contains(where: { $0.pace != nil }) {
            chartCard(title: "Pace", unit: "min/km", role: .hrv, id: "activity-detail-pace-chart",
                      values: points.compactMap { p in p.pace.map { (p.minute, $0) } }, reversed: true)
        }
        let rows = activitySplitRows(s)
        if !rows.isEmpty { splitTable(rows) }
        Text(s.caption).jiFont(.caption).foregroundStyle(theme.color(.muted))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("activity-detail-caption")
    }

    private func chartCard(title: String, unit: String, role: JIColorRole, id: String,
                           values: [(Double, Double)], reversed: Bool) -> some View {
        Surface(level: 1) {
            VStack(alignment: .leading, spacing: JISpacing.s2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                    Spacer()
                    Text(unit).jiFont(.caption).foregroundStyle(theme.color(.muted))
                }
                Chart(Array(values.enumerated()), id: \.offset) { item in
                    LineMark(x: .value("Minute", item.element.0), y: .value(title, item.element.1))
                        .foregroundStyle(theme.color(role))
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: .automatic(includesZero: false, reversed: reversed))
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel { if let m = value.as(Double.self) { Text(activityAxisMinuteText(m, span: values.last?.0 ?? 0)) } }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(reversed ? (activityPaceText(v * 60) ?? "") : "\(Int(v.rounded()))")
                            }
                        }
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("\(title) over the workout")
            }
        }
        .accessibilityIdentifier(id)
    }

    private func splitTable(_ rows: [ActivitySplitRow]) -> some View {
        Surface(level: 1) {
            VStack(alignment: .leading, spacing: JISpacing.s2) {
                Text("Splits").jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                    .accessibilityAddTraits(.isHeader)
                Grid(alignment: .trailing, horizontalSpacing: JISpacing.s3, verticalSpacing: 6) {
                    GridRow {
                        Text("km").gridColumnAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        Text("Pace /km"); Text("HR"); Text("Elev m")
                    }
                    .jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
                    Divider().overlay(theme.color(.hairlineNested)).gridCellUnsizedAxes(.horizontal)
                    ForEach(rows) { r in
                        GridRow {
                            Text(r.label).foregroundStyle(theme.color(.text)).gridColumnAlignment(.leading)
                            Text(r.pace).foregroundStyle(theme.color(.text)).monospacedDigit()
                            Text(r.hr).foregroundStyle(theme.color(.muted)).monospacedDigit()
                            Text(r.elevation).foregroundStyle(theme.color(.muted)).monospacedDigit()
                        }
                        .jiFont(.subheadline)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Kilometre \(r.label), pace \(r.pace), heart rate \(r.hr), elevation \(r.elevation)")
                        .accessibilityIdentifier("activity-split-\(r.id)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("activity-detail-splits")
        .id("splits")
    }

    private func note(_ title: String, _ detail: String) -> some View {
        Surface(level: 1) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                Text(detail).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
/// Gallery: the Garmin run 23926763203 as the hub served it (2026-10-06), points thinned.
public struct ActivityDetailNativePreview: View {
    public init() {}
    public var body: some View {
        NavigationStack {
            ActivityDetailView(model: ActivityDetailModel(
                activity: DayActivity(activityId: 23926763203, type: "running", name: nil, durationSec: 4818,
                                      distanceM: 6694, source: "garmin", avgHr: 122),
                provider: ActivityDetailFixtureProvider()))
        }
    }
}

nonisolated struct ActivityDetailFixtureProvider: ActivitySeriesProviding {
    func activitySeries(activityId: Int) async throws -> ActivitySeries {
        let paces: [Double] = [840.55, 777.01, 751.32, 689.67, 655.69, 605.29, 694.99]
        let hrs: [Double] = [121.1, 124.2, 122.5, 121.8, 124.6, 125.4, 119.2]
        let elev: [Double] = [7.3, 5.3, 5.0, 12.9, 6.4, 4.1, 5.3]
        let splits = (0..<7).map { i in
            ActivitySplit(km: i + 1, distanceM: i == 6 ? 694.21 : 1000, durationS: i == 6 ? 482.46 : paces[i],
                          paceSPerKm: paces[i], meanHr: hrs[i], elevationGainM: elev[i])
        }
        var t = 0.0
        let points: [ActivitySeriesPoint] = (0..<60).map { i in
            defer { t += 80 }
            let km = min(6, Int(t / 700))
            return ActivitySeriesPoint(t: t, hr: hrs[km] + sin(Double(i) / 3) * 3, paceSPerKm: paces[km] + cos(Double(i) / 2) * 15)
        }
        return ActivitySeries(activityId: activityId, type: "running", splits: splits, points: points,
                              hrOnly: false, caption: "JI-computed, may differ from Garmin")
    }
}
#endif
