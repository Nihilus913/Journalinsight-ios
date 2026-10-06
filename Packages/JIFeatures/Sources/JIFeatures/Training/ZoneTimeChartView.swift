import Charts
import JICore
import JIDesign
import Observation
import SwiftUI

/// B-95 (BP-26, mockup `docs/waves/mockups/bevel/BP-26.html`) — time in HR zone over W / M / 6M.
/// The hub re-bins every session's HR samples with the user's CURRENT zones
/// (`GET /api/v1/training/zones`), so weeks before a zone change stay comparable.
/// W = daily bars Mon–Sun, M = 5 weekly bars, 6M = 26 weekly bars (hours). A bucket without HR
/// draws no bar (rule 5: never a zero for missing data).
public enum ZoneTimeSpan: String, CaseIterable, Identifiable, Sendable {
    case week = "W", month = "M", sixMonths = "6M"
    public var id: String { rawValue }

    /// (from, to, bucket) for `today` — W: this Mon–Sun by day; M / 6M: 5 / 26 Mon-weeks ending this week.
    public func window(today: DayKey) -> (from: DayKey, to: DayKey, bucket: String) {
        let monday = today.mondayOfWeek
        switch self {
        case .week: return (monday, monday.adding(days: 6), "day")
        case .month: return (monday.adding(days: -28), today, "week")
        case .sixMonths: return (monday.adding(days: -25 * 7), today, "week")
        }
    }

    /// 6M reads in hours, W / M in minutes.
    var usesHours: Bool { self == .sixMonths }
}

/// W-FIX-P3 RG-62: which sessions count — the hub's `scope=cardio|all`.
public nonisolated enum ZoneTimeScope: String, CaseIterable, Identifiable, Sendable {
    case cardio, all
    public var id: String { rawValue }
    public var title: String { self == .cardio ? "Cardio" : "All workouts" }
}

@MainActor @Observable
public final class ZoneTimeModel {
    public enum Phase: Equatable { case loading, loaded(ZoneTimeRange), unavailable, error(String) }
    public private(set) var phase: Phase = .loading
    /// W-FIX-P3 RG-69 (B-52): set while the shown range is the hub's offline cached copy.
    public private(set) var staleSince: Date?
    public var span: ZoneTimeSpan
    /// W-FIX-P3 RG-62: cardio by default; "All workouts" adds strength and the rest.
    public var scope: ZoneTimeScope = .cardio
    @ObservationIgnored private let provider: (any ZoneTimeProviding)?
    @ObservationIgnored private let today: () -> DayKey

    public init(provider: (any ZoneTimeProviding)?, span: ZoneTimeSpan = .week, today: @escaping () -> DayKey) {
        self.provider = provider; self.span = span; self.today = today
    }

    public func load() async {
        guard let provider else { phase = .unavailable; return }
        let w = span.window(today: today())
        // W-FIX-P3 RG-62: a loaded range of ANOTHER span/scope is replaced by the spinner at once —
        // the old bars never sit under the new picker value. A same-window refresh keeps them.
        if case .loaded(let r) = phase, r.from == w.from.iso, r.bucket == w.bucket, r.scope == scope.rawValue {} else { phase = .loading }
        do {
            let (range, since) = try await HubReadTrace.collect {
                try await provider.trainingZones(from: w.from.iso, to: w.to.iso, bucket: w.bucket, scope: scope.rawValue)
            }
            phase = .loaded(range); staleSince = since
        } catch HubError.http(status: 404, _) {
            phase = .unavailable
        } catch {
            phase = .error(zoneTimeErrorText(error))
        }
    }

    /// "Offline — showing data from 07:41" while the shown range is the cached copy.
    public var offlineText: String? { staleSince.map { offlineReadCaption(since: $0) } }
}

struct ZoneBarPoint: Identifiable {
    let id: String
    let label: String
    let zone: Int
    let value: Double
}

/// Bars for the chart: one point per (bucket, zone) with minutes > 0; buckets without HR give none.
func zoneBarPoints(_ r: ZoneTimeRange, span: ZoneTimeSpan) -> [ZoneBarPoint] {
    r.buckets.flatMap { b -> [ZoneBarPoint] in
        let label = zoneBucketLabel(b.start, span: span)
        guard let m = b.minutes else { return [] }
        return m.enumerated().compactMap { i, v in
            v > 0 ? ZoneBarPoint(id: "\(b.start)-\(i)", label: label, zone: i + 1, value: span.usesHours ? v / 60 : v) : nil
        }
    }
}

func zoneBucketLabel(_ iso: String, span: ZoneTimeSpan) -> String {
    guard let d = DayKey(iso: iso) else { return iso }
    return span == .week ? d.string(format: "EEE") : d.string(format: "d MMM")
}

/// W-FIX-P3 RG-62: what the user reads when the range fails — never a raw Swift error string.
nonisolated func zoneTimeErrorText(_ error: any Error) -> String {
    let offline = "Can't reach the hub — check your connection and pull to retry."
    switch error {
    case HubError.unauthorized: return "The hub rejected the token — check Settings › Connection."
    case HubError.network: return offline
    case HubError.decoding: return "The hub sent data this app can't read — update the app or the hub."
    case HubError.http(let status, _): return "The hub couldn't build this range (error \(status)). Try again later."
    case is URLError: return offline
    default: return "Something went wrong loading time in zone. Pull to retry."
    }
}

/// W-FIX-P3 RG-62: all five floors ("Your zones · Z1 97 · Z2 117 · … bpm").
nonisolated func zoneFloorsText(_ floors: [Int]) -> String {
    "Your zones · " + floors.enumerated().map { "Z\($0.offset + 1) \($0.element)" }.joined(separator: " · ") + " bpm"
}

/// W-FIX-P3 RG-62: the x labels drawn — every 2nd at an accessibility text size (W, M), every
/// 5th (6M) / 10th at AX — so neighbouring labels never overlap.
nonisolated func zoneAxisLabels(_ labels: [String], span: ZoneTimeSpan, accessibility: Bool) -> [String] {
    let step: Int = switch span {
    case .week, .month: accessibility ? 2 : 1
    case .sixMonths: accessibility ? 10 : 5
    }
    return labels.enumerated().filter { $0.offset % step == 0 }.map(\.element)
}

func zoneTotalText(_ minutes: Double) -> String {
    minutes >= 120 ? String(format: "%.1f h", minutes / 60) : "\(Int(minutes.rounded())) min"
}

public struct ZoneTimeChartView: View {
    @Bindable var model: ZoneTimeModel
    private let theme = JITheme.native
    @Environment(\.dynamicTypeSize) private var typeSize
    public init(model: ZoneTimeModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JISpacing.s3) {
                Picker("Range", selection: $model.span) {
                    ForEach(ZoneTimeSpan.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("zone-time-range")
                // W-FIX-P3 RG-62: scope selectable (cardio / all workouts).
                Picker("Sessions", selection: $model.scope) {
                    ForEach(ZoneTimeScope.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("zone-time-scope")
                content
            }
            .padding(.horizontal, JISpacing.s4).padding(.vertical, JISpacing.s3)
        }
        .background(theme.color(.bg).ignoresSafeArea())
        .navigationTitle("Time in zone")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task(id: "\(model.span.rawValue)-\(model.scope.rawValue)") { await model.load() }
        .refreshable { await model.load() }
        .jiTheme(.native)
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
            .accessibilityIdentifier("zone-time-loading")
        case .unavailable:
            note("Time in zone needs the hub.", "Connect to a hub that serves /training/zones.")
        case .error(let message):
            note("Couldn't load time in zone.", message)
                .accessibilityIdentifier("zone-time-error")
        case .loaded(let r):
            loaded(r)
        }
    }

    @ViewBuilder private func loaded(_ r: ZoneTimeRange) -> some View {
        if let offline = model.offlineText {
            Text(offline).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                .accessibilityIdentifier("zone-time-offline")
        }
        if let floors = r.floors {
            Text(zoneFloorsText(floors))
                .jiFont(.caption).foregroundStyle(theme.color(.muted))
            let w = model.span.window(today: DayKey(iso: r.to) ?? DayKey.today())
            Surface(level: 1) {
                VStack(alignment: .leading, spacing: JISpacing.s2) {
                    Text("\(w.from.string(format: "d MMM")) – \(DayKey(iso: r.to)?.string(format: "d MMM") ?? r.to)")
                        .jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                    Text((model.span.usesHours ? "Hours per week" : (model.span == .week ? "Min per day" : "Min per week"))
                         + (model.scope == .cardio ? " · cardio" : " · all workouts"))
                        .jiFont(.caption).foregroundStyle(theme.color(.muted))
                    if r.totals.minutes == nil {
                        Text("No session with an HR stream in this range." + (r.totals.sessionsNoHr > 0 ? " \(r.totals.sessionsNoHr) without HR — shown as \"no HR\", never 0." : ""))
                            .jiFont(.body).foregroundStyle(theme.color(.muted))
                            .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
                            .accessibilityIdentifier("zone-time-empty")
                    } else {
                        chart(r)
                    }
                }
            }
            legend(r)
            Text("Re-binned from HR samples with your current zones (10 s gap cap); Apple's own zone split only when a session has no samples.")
                .jiFont(.caption).foregroundStyle(theme.color(.muted)).fixedSize(horizontal: false, vertical: true)
        } else {
            note("Set your zones first", "Zones are your input — enter five floors in Settings › Training › HR zones.")
        }
    }

    private func chart(_ r: ZoneTimeRange) -> some View {
        let labels = r.buckets.map { zoneBucketLabel($0.start, span: model.span) }
        return Chart(zoneBarPoints(r, span: model.span)) { p in
            BarMark(x: .value("Bucket", p.label), y: .value(model.span.usesHours ? "Hours" : "Minutes", p.value))
                .foregroundStyle(by: .value("Zone", "Z\(p.zone)"))
        }
        .chartForegroundStyleScale(domain: (1...5).map { "Z\($0)" },
                                   range: (1...5).map { theme.color(workoutZoneRole($0)) })
        .chartXScale(domain: labels)
        .chartXAxis {
            // 6M: 26 weekly bars — label every 5th week; RG-62: fewer again at accessibility sizes.
            let shown = Set(zoneAxisLabels(labels, span: model.span, accessibility: typeSize.isAccessibilitySize))
            AxisMarks { value in
                if let s = value.as(String.self), shown.contains(s) {
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
        }
        .chartYAxis { AxisMarks(position: .trailing) }
        .chartLegend(.hidden)
        .frame(height: 220)
        .accessibilityIdentifier("zone-time-chart")
    }

    private func legend(_ r: ZoneTimeRange) -> some View {
        let m = r.totals.minutes ?? []
        return Surface(level: 1) {
            VStack(alignment: .leading, spacing: JISpacing.s2) {
                ForEach(1...5, id: \.self) { z in
                    HStack {
                        Circle().fill(theme.color(workoutZoneRole(z))).frame(width: 10, height: 10)
                        Text(z == 5 && r.hrCapBpm != nil ? "Z5 · above cap" : "Z\(z)")
                            .jiFont(.body).foregroundStyle(theme.color(.text))
                        Spacer()
                        Text(m.count == 5 ? zoneTotalText(m[z - 1]) : "— no HR")
                            .jiFont(.body, weight: .semibold).foregroundStyle(theme.color(m.count == 5 ? .text : .muted))
                    }
                }
                if m.count == 5 {
                    let total = m.reduce(0, +)
                    let z2 = total > 0 ? Int((m[1] / total * 100).rounded()) : 0
                    JIRowDivider()
                    Text("\(r.totals.sessions) sessions · \(zoneTotalText(total)) with HR · Z2 \(z2) % · hard Z4+Z5 \(zoneTotalText(m[3] + m[4]))")
                        .jiFont(.caption).foregroundStyle(theme.color(.muted)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("zone-time-legend")
    }

    private func note(_ title: String, _ body: String) -> some View {
        Surface(level: 1) {
            VStack(alignment: .leading, spacing: JISpacing.s2) {
                Text(title).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                Text(body).jiFont(.caption).foregroundStyle(theme.color(.muted)).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Identity-hashed so `navigationDestination(item:)` can push one model instance.
extension ZoneTimeModel: Hashable {
    public nonisolated static func == (a: ZoneTimeModel, b: ZoneTimeModel) -> Bool { a === b }
    public nonisolated func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }
}
