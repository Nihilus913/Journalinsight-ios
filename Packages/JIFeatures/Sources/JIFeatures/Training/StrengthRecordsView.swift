import SwiftUI
import Charts
import JICore
import JICompute
import JIDesign

/// B-89 BP-6a mockup screen 1 — Records: one row per lift (best e1RM, heaviest, last session).
public struct StrengthRecordsView: View {
    @Bindable private var model: StrengthRecordsViewModel
    @State private var openLift: String?
    private let theme = JITheme.native

    public init(model: StrengthRecordsViewModel) { self.model = model }

    public var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                Text(subtitle).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("strength-records-subtitle")
                if let error = model.hubError {
                    Text("Showing what this phone has — \(error)").jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    JISectionHeader("Strength · estimated 1RM")
                    Surface(level: 1, padding: 0) {
                        VStack(spacing: 0) {
                            if model.lifts.isEmpty {
                                Text(model.loading ? "Loading records…" : "No sets yet. Records appear after the first logged session.")
                                    .jiFont(.body).foregroundStyle(theme.color(.muted)).padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("strength-records-empty")
                            }
                            ForEach(Array(model.lifts.enumerated()), id: \.element.id) { i, lift in
                                if i > 0 { Divider().padding(.leading, 16) }
                                Button { model.selected = lift.lift; openLift = lift.lift } label: { row(lift) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("strength-records-\(lift.lift)")
                            }
                        }
                    }
                }
                Text(StrengthRecordsFormat.methodNote(hasGarmin: model.hasGarmin))
                    .jiFont(.caption).foregroundStyle(theme.color(.muted)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
        .jiTheme(.native)
        .navigationTitle("Records")
        .refreshable { await model.load() }
        .task { await model.load() }
        .navigationDestination(item: $openLift) { _ in StrengthLiftDetailView(model: model) }
    }

    private var subtitle: String {
        let n = model.lifts.count
        guard let first = model.lifts.flatMap({ $0.sessions.map(\.date) }).min() else { return "Strength · no sets yet" }
        return "Strength · \(n) lift\(n == 1 ? "" : "s") with sets · since \(StrengthRecordsFormat.monthYear(first))"
    }

    private func row(_ lift: OneRepMax.LiftHistory) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(StrengthRecordsFormat.liftTitle(lift.lift)).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                Text(StrengthRecordsFormat.rowDetail(lift)).jiFont(.caption).foregroundStyle(theme.color(.muted))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(StrengthRecordsFormat.kg1(lift.records.bestE1rm?.value)).jiFont(.numeralSmall, design: .rounded)
                    .foregroundStyle(theme.color(.text)).monospacedDigit()
                Text("e1RM kg").jiFont(.micro).foregroundStyle(theme.color(.muted))
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(theme.color(.muted))
        }
        .padding(.horizontal, 16).frame(minHeight: 56).padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Mockup screens 2–4 — one lift: chips, hero numeral + status, e1RM chart with PR dots and the
/// dashed best, record tiles, sessions newest first.
struct StrengthLiftDetailView: View {
    @Bindable var model: StrengthRecordsViewModel
    @State private var range: TrendRange = .sixMonths
    private let theme = JITheme.native

    var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                chips
                if let lift = model.selectedLift {
                    hero(lift)
                    records(lift)
                    sessions(lift)
                } else if model.loading {
                    SkeletonBlock(width: 120, height: 40); SkeletonBlock(height: 180)
                }
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
        .jiTheme(.native)
        .navigationTitle(model.selectedLift.map { StrengthRecordsFormat.liftTitle($0.lift) } ?? "Records")
        .refreshable { await model.load() }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.lifts) { l in
                    let on = l.lift == model.selectedLift?.lift
                    Button { model.selected = l.lift } label: {
                        Text(StrengthRecordsFormat.liftTitle(l.lift)).jiFont(.caption, weight: .semibold)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundStyle(on ? Color.white : theme.color(.text))
                            .background(Capsule().fill(on ? theme.color(.info) : theme.color(.control)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("strength-lift-chip-\(l.lift)")
                }
            }
        }
    }

    private func hero(_ lift: OneRepMax.LiftHistory) -> some View {
        let status = OneRepMax.status(lift)
        let calibrating = lift.sessions.count < 3
        return Surface(level: 1, padding: JISpacing.cardPadding) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(StrengthRecordsFormat.kg0(lift.latest?.e1rm)).jiFont(.numeralHero, design: .rounded)
                        .foregroundStyle(theme.color(.text)).monospacedDigit()
                    Text("kg e1RM").jiFont(.body).foregroundStyle(theme.color(.muted))
                }
                .accessibilityIdentifier("strength-lift-hero")
                Text(StrengthRecordsFormat.statusLine(status)).jiFont(.body, weight: .semibold)
                    .foregroundStyle(theme.color(StrengthRecordsFormat.statusRole(status)))
                Text(StrengthRecordsFormat.summary(lift)).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Range", selection: $range) {
                    ForEach([TrendRange.week, .month, .sixMonths, .year]) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Estimated 1RM · \(StrengthRecordsFormat.rangeName(range)) · \(model.hasGarmin ? "Garmin + JI log" : "JI log")")
                    .jiFont(.micro, weight: .semibold).foregroundStyle(theme.color(.muted))
                if calibrating {
                    Text("Trend after 3 sessions · \(lift.sessions.count) so far").jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    chart(lift)
                }
                HStack(spacing: 14) {
                    Label("PR = beats every earlier session", systemImage: "circle.fill").labelStyle(.titleAndIcon)
                    Text("dashed = your best")
                }
                .jiFont(.micro).foregroundStyle(theme.color(.muted))
            }
        }
    }

    private func chart(_ lift: OneRepMax.LiftHistory) -> some View {
        let anchor = StrengthRecordsFormat.date(lift.latest?.date ?? "") ?? Date()
        let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -range.days, to: anchor) ?? anchor
        let pts = lift.sessions.reversed().compactMap { s -> (Date, Double, Bool)? in
            guard let d = StrengthRecordsFormat.date(s.date), d >= cutoff else { return nil }
            return (d, s.e1rm, s.prs.contains(.e1rm))
        }
        let best = lift.records.bestE1rm?.value
        return Chart {
            ForEach(pts, id: \.0) { p in
                LineMark(x: .value("Date", p.0), y: .value("kg", p.1))
                    .foregroundStyle(theme.color(.text)).interpolationMethod(.monotone)
                if p.2 {
                    PointMark(x: .value("Date", p.0), y: .value("kg", p.1))
                        .foregroundStyle(theme.color(.go)).symbolSize(60)
                }
            }
            if let best {
                RuleMark(y: .value("Best", best))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(theme.color(.muted))
                    .annotation(position: .top, alignment: .leading) {
                        Text("best \(StrengthRecordsFormat.kg1(best))").jiFont(.micro).foregroundStyle(theme.color(.muted))
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis { AxisMarks(position: .trailing) }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
        .frame(height: 180)
        .overlay { if pts.isEmpty { Text("No sessions in this range").jiFont(.footnote).foregroundStyle(theme.color(.muted)) } }
        .accessibilityIdentifier("strength-lift-chart")
    }

    private func records(_ lift: OneRepMax.LiftHistory) -> some View {
        let r = lift.records, few = lift.sessions.count < 3
        return VStack(alignment: .leading, spacing: 0) {
            JISectionHeader("Records")
            HStack(spacing: 8) {
                tile("Heaviest", StrengthRecordsFormat.kg0(r.heaviest?.value) + " kg",
                     r.heaviest.map { "first \(StrengthRecordsFormat.dayMonth($0.date))" } ?? "—")
                tile("Best e1RM", few ? "—" : StrengthRecordsFormat.kg1(r.bestE1rm?.value) + " kg",
                     few ? "after 3 sessions" : r.bestE1rm.map { "\(StrengthRecordsFormat.dayMonth($0.date)) · \(StrengthRecordsFormat.setText($0.set))" } ?? "—")
                tile("Best volume", StrengthRecordsFormat.grouped(r.bestVolume?.value) + " kg",
                     r.bestVolume.map { "\(StrengthRecordsFormat.dayMonth($0.date)) · \($0.reps ?? 0) reps" } ?? "—")
            }
            .accessibilityIdentifier("strength-lift-records")
        }
    }

    private func tile(_ title: String, _ value: String, _ detail: String) -> some View {
        Surface(level: 1, padding: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).jiFont(.micro, weight: .semibold).foregroundStyle(theme.color(.muted))
                Text(value).jiFont(.cardTitle, design: .rounded).foregroundStyle(theme.color(.text)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).jiFont(.micro).foregroundStyle(theme.color(.muted)).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func sessions(_ lift: OneRepMax.LiftHistory) -> some View {
        let bestE1 = lift.records.bestE1rm?.value
        return VStack(alignment: .leading, spacing: 0) {
            JISectionHeader("Sessions")
            Surface(level: 1, padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(lift.sessions.prefix(5).enumerated()), id: \.element.id) { i, s in
                        if i > 0 { Divider().padding(.leading, 16) }
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(StrengthRecordsFormat.weekdayDayMonth(s.date)).jiFont(.body, weight: .semibold)
                                        .foregroundStyle(theme.color(.text))
                                    if !s.prs.isEmpty {
                                        Text("PR").jiFont(.micro, weight: .bold).foregroundStyle(theme.color(.go))
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Capsule().fill(theme.color(.go).opacity(0.18)))
                                    }
                                }
                                Text(s.sets.map(StrengthRecordsFormat.setText).joined(separator: " · ") + " · \(StrengthRecordsFormat.grouped(s.volumeKg)) kg")
                                    .jiFont(.caption).foregroundStyle(theme.color(.muted)).lineLimit(2)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(StrengthRecordsFormat.kg1(s.e1rm)).jiFont(.body, weight: .semibold, design: .rounded)
                                    .foregroundStyle(theme.color(.text)).monospacedDigit()
                                Text(StrengthRecordsFormat.sessionTag(s, best: bestE1)).jiFont(.micro).foregroundStyle(theme.color(.muted))
                            }
                        }
                        .padding(.horizontal, 16).frame(minHeight: 56).padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                    if lift.sessions.count > 5 {
                        Divider().padding(.leading, 16)
                        Text("\(lift.sessions.count) sessions in all").jiFont(.caption).foregroundStyle(theme.color(.muted))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 16)
                    }
                }
            }
            .accessibilityIdentifier("strength-lift-sessions")
            Text("A tie is not a record. Sets under \(Int(OneRepMax.minKg(lift.lift))) kg\(lift.perHand ? " per hand" : "") or over \(OneRepMax.maxReps) reps are not counted.")
                .jiFont(.caption).foregroundStyle(theme.color(.muted)).padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Text for the Records screens (pure, unit-tested).
nonisolated enum StrengthRecordsFormat {
    static func liftTitle(_ lift: String) -> String {
        switch lift {
        case "Barbell Bench Press": "Bench press"
        case "Barbell Row": "Row"
        case "DB Shoulder Press": "Shoulder press"
        case "DB Biceps Curl": "Curl"
        case "KB Overhead Triceps Extension": "Triceps extension"
        default: lift
        }
    }

    static func kg1(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "—" }
    static func kg0(_ v: Double?) -> String { v.map { String(format: "%.0f", $0) } ?? "—" }
    static func grouped(_ v: Double?) -> String {
        guard let v else { return "—" }
        let n = Int(v.rounded())
        return n >= 1000 ? "\(n / 1000) \(String(format: "%03d", n % 1000))" : "\(n)"
    }
    static func setText(_ s: OneRepMax.LiftSet?) -> String {
        guard let s else { return "—" }
        let w = s.weightKg.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", s.weightKg) : String(format: "%.1f", s.weightKg)
        return "\(w) × \(s.reps)"
    }

    private static let iso: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static func fmt(_ template: String) -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = template; return f
    }
    static func date(_ s: String) -> Date? { iso.date(from: String(s.prefix(10))) }
    static func dayMonth(_ s: String) -> String { date(s).map { fmt("d MMM").string(from: $0) } ?? s }
    static func weekdayDayMonth(_ s: String) -> String { date(s).map { fmt("EEE d MMM").string(from: $0) } ?? s }
    static func monthYear(_ s: String) -> String { date(s).map { fmt("MMM yyyy").string(from: $0) } ?? s }

    static func rowDetail(_ l: OneRepMax.LiftHistory) -> String {
        let heavy = "heaviest \(kg0(l.records.heaviest?.value)) kg\(l.perHand ? " per hand" : "")"
        let last = l.latest.map { " · last \(dayMonth($0.date)) · \(kg1($0.e1rm))" } ?? ""
        return heavy + last
    }

    static func statusLine(_ s: OneRepMax.Status) -> String {
        switch s {
        case .none: "No sessions yet"
        case .first: "First session · nothing to compare with yet"
        case .newBest: "New best"
        case .held: "Held vs your best of the last 4 weeks"
        case .down(let p): "Down \(p) % vs your best of the last 4 weeks"
        }
    }
    static func statusRole(_ s: OneRepMax.Status) -> JIColorRole {
        switch s { case .newBest: .go; case .down: .reduced; default: .text }
    }

    static func summary(_ l: OneRepMax.LiftHistory) -> String {
        guard l.sessions.count >= 3 else {
            return "\(l.sessions.count == 1 ? "One session" : "\(l.sessions.count) sessions") logged. The trend and your first records appear after three."
        }
        guard let b = l.records.bestE1rm else { return "" }
        return "Best \(kg1(b.value)) on \(dayMonth(b.date)) (\(setText(b.set)))."
    }

    static func sessionTag(_ s: OneRepMax.Session, best: Double?) -> String {
        if !s.prs.isEmpty { return s.prs.map { $0 == .e1rm ? "e1RM" : $0.rawValue }.joined(separator: " · ") }
        if let best, s.e1rm == best { return "ties best" }
        return "e1RM"
    }

    static func rangeName(_ r: TrendRange) -> String {
        switch r { case .day: "1 day"; case .week: "1 week"; case .month: "this month"; case .sixMonths: "6 months"; case .year: "1 year" }
    }

    static func methodNote(hasGarmin: Bool) -> String {
        "Epley, best set per session, reps ≤ \(OneRepMax.maxReps), sets under 20 kg (4 kg dumbbell) ignored. "
            + (hasGarmin ? "Garmin history + the JI log. " : "The JI log. ") + "Estimated, not tested."
    }
}
