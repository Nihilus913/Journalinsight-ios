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

@MainActor @Observable
public final class ZoneTimeModel {
    public enum Phase: Equatable { case loading, loaded(ZoneTimeRange), unavailable, error(String) }
    public private(set) var phase: Phase = .loading
    public var span: ZoneTimeSpan
    @ObservationIgnored private let provider: (any ZoneTimeProviding)?
    @ObservationIgnored private let today: () -> DayKey

    public init(provider: (any ZoneTimeProviding)?, span: ZoneTimeSpan = .week, today: @escaping () -> DayKey) {
        self.provider = provider; self.span = span; self.today = today
    }

    public func load() async {
        guard let provider else { phase = .unavailable; return }
        let w = span.window(today: today())
        if case .loaded = phase {} else { phase = .loading }
        do {
            phase = .loaded(try await provider.trainingZones(from: w.from.iso, to: w.to.iso, bucket: w.bucket, scope: "cardio"))
        } catch HubError.http(status: 404, _) {
            phase = .unavailable
        } catch {
            phase = .error(String(describing: error))
        }
    }
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

func zoneTotalText(_ minutes: Double) -> String {
    minutes >= 120 ? String(format: "%.1f h", minutes / 60) : "\(Int(minutes.rounded())) min"
}

public struct ZoneTimeChartView: View {
    @Bindable var model: ZoneTimeModel
    private let theme = JITheme.native
    public init(model: ZoneTimeModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JISpacing.s3) {
                Picker("Range", selection: $model.span) {
                    ForEach(ZoneTimeSpan.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("zone-time-range")
                content
            }
            .padding(.horizontal, JISpacing.s4).padding(.vertical, JISpacing.s3)
        }
        .background(theme.color(.bg).ignoresSafeArea())
        .navigationTitle("Time in zone")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task(id: model.span) { await model.load() }
        .jiTheme(.native)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            Surface(level: 1) { RoundedRectangle(cornerRadius: 12).fill(theme.color(.muted).opacity(0.12)).frame(height: 220) }
                .accessibilityLabel("Loading")
        case .unavailable:
            note("Time in zone needs the hub.", "Connect to a hub that serves /training/zones.")
        case .error(let message):
            note("Couldn't load time in zone.", message)
        case .loaded(let r):
            loaded(r)
        }
    }

    @ViewBuilder private func loaded(_ r: ZoneTimeRange) -> some View {
        if let floors = r.floors {
            Text("Your zones · " + floors.dropFirst().map(String.init).joined(separator: " / ") + " bpm")
                .jiFont(.caption).foregroundStyle(theme.color(.muted))
            let w = model.span.window(today: DayKey(iso: r.to) ?? DayKey.today())
            Surface(level: 1) {
                VStack(alignment: .leading, spacing: JISpacing.s2) {
                    Text("\(w.from.string(format: "d MMM")) – \(DayKey(iso: r.to)?.string(format: "d MMM") ?? r.to)")
                        .jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                    Text(model.span.usesHours ? "Hours per week · cardio" : (model.span == .week ? "Min per day · cardio" : "Min per week · cardio"))
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
            // 6M: 26 weekly bars — label every 5th week so the dates stay legible.
            let shown = Set(model.span == .sixMonths ? labels.enumerated().filter { $0.offset % 5 == 0 }.map(\.element) : labels)
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
