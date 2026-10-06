import Foundation
import Observation
import JICore
import JICompute
import JIDesign
import JIPersistence

/// B-94 b94p4 (Bevel BP-4) — one chart card on the Progress screen.
public nonisolated struct ProgressCard: Sendable, Equatable, Identifiable {
    public enum Section: String, Sendable, Equatable { case strength, cardio }

    public let id: ProgressChartID
    public let section: Section
    /// "Bench press · Est. 1RM"
    public let title: String
    /// Points inside the selected range, oldest first.
    public let points: [TrendPoint]
    public let unit: String
    public let kind: TrendChartKind
    /// Sessions / runs / readings inside the range that carry a value.
    public let count: Int
    public let pinned: Bool
    /// Caption under the chart ("Est. 1RM (Epley) · 6 months · heaviest session per week").
    public let caption: String
    /// RG-11 / B-126: one line per source (VO₂ max: Apple solid, Garmin dashed "est."); empty =
    /// draw `points` as one line.
    public var series: [TrendSeries] = []
    /// Source of the newest reading, appended to the headline ("25.0 Apple").
    public var headlineSource: String? = nil

    /// "Not enough data yet" — fewer than 3 sessions / runs / readings in range (rule 5: never a
    /// false zero, never a one-point line).
    public var thin: Bool { count < ProgressViewModel.minPoints }
    /// Headline = the newest value in range, formatted (U+202F groups); nil when thin.
    public var headline: String? {
        guard !thin, let last = points.last else { return nil }
        let v = ProgressFormat.value(last.value, metric: id)
        return headlineSource.map { "\(v) \($0)" } ?? v
    }
}

/// B-94 b94p4 — the Progress screen: Strength (per-lift charts over `LiftSeries`) + Cardio
/// (runs + VO₂ max from `GET /training/cardio-series`). Charts shown = pins first (pin order),
/// then the default catalogue (each lift's lead metric, run pace, VO₂ max), hidden ones left out.
/// Pins are local (`PrefStore` key `progress_charts.prefs.v1`, no sync; card Q2).
@Observable @MainActor
public final class ProgressViewModel {
    public nonisolated static let minPoints = LiftSeries.minSessions
    /// Cardio is fetched once at the widest range and cut per range locally.
    public nonisolated static let cardioFetchRange = "y"

    public private(set) var prefs = ProgressChartSelection.defaultPrefs()
    public var range: TrendRange = .sixMonths
    public private(set) var loading = false
    public private(set) var strengthError: String?
    public private(set) var cardioError: String?
    public private(set) var liftInputs: [LiftSeries.Input] = []
    public private(set) var cardio: CardioSeries?

    private let store: StrengthSessionLogStore?
    private let provider: (any TrainingProviding)?
    private let cardioProvider: (any CardioSeriesProviding)?
    private let prefStore: (any JIPrefStoring)?
    private let today: () -> String
    private var hub: StrengthRecordsOut?
    /// W-FIX-P3 RG-69 (B-52): set while a section shows the hub's offline cached copy.
    public private(set) var strengthStaleSince: Date?
    public private(set) var cardioStaleSince: Date?

    /// "Offline — showing data from 07:41" (the oldest cached copy shown), nil when all is live.
    public var offlineText: String? {
        [strengthStaleSince, cardioStaleSince].compactMap { $0 }.min().map { offlineReadCaption(since: $0) }
    }

    public init(store: StrengthSessionLogStore?, provider: (any TrainingProviding)?,
                cardioProvider: (any CardioSeriesProviding)?, prefStore: (any JIPrefStoring)?,
                today: @escaping () -> String) {
        self.store = store; self.provider = provider; self.cardioProvider = cardioProvider
        self.prefStore = prefStore; self.today = today
        loadPrefs()
    }

    // MARK: - Load

    public func load() async {
        loadPrefs()
        recomputeLifts()
        loading = hub == nil && cardio == nil
        async let s: Void = loadStrength()
        async let c: Void = loadCardio()
        _ = await (s, c)
        loading = false
    }

    private func loadStrength() async {
        guard let provider else { return }
        do {
            let (value, since) = try await HubReadTrace.collect { try await provider.strengthRecords() }
            hub = value; strengthStaleSince = since
            strengthError = nil
        } catch is StrengthRecordsUnavailable {
            strengthError = nil
        } catch {
            strengthError = StrengthOutbox.describe(error)
        }
        recomputeLifts()
    }

    private func loadCardio() async {
        guard let cardioProvider else { return }
        do {
            let (value, since) = try await HubReadTrace.collect {
                try await cardioProvider.cardioSeries(range: Self.cardioFetchRange)
            }
            cardio = value; cardioStaleSince = since
            cardioError = nil
        } catch {
            cardioError = StrengthOutbox.describe(error)
        }
    }

    /// Hub history (Garmin + hub-stored JI logs) + this phone's log. A lift × day the hub already
    /// holds as a JI log is not read twice from the phone; Garmin-vs-JI of one day is
    /// `LiftSeries.dedupe`'s job.
    func recomputeLifts() {
        var inputs: [LiftSeries.Input] = []
        var hubLogged = Set<String>()
        for l in hub?.lifts ?? [] {
            for s in l.sessions {
                let logged = s.sources?.contains("logged") == true
                if logged { hubLogged.insert("\(l.lift)|\(s.date)") }
                let source = s.sources?.contains("garmin") == true ? "garmin" : LiftSeries.loggedSource
                for x in s.sets {
                    inputs.append(.init(lift: l.lift, date: s.date, reps: x.reps, weightKg: x.weightKg, source: source))
                }
            }
        }
        if let store {
            let to = today()
            let from = (try? CalendarMath.addDays(to, -3650)) ?? "2000-01-01"
            for s in (try? store.sessions(from: from, to: to)) ?? [] {
                for x in (try? store.sets(sessionClientId: s.clientId)) ?? [] {
                    let lift = StrengthRecordsViewModel.planLift(x.exerciseKey) ?? x.exerciseKey
                    guard !hubLogged.contains("\(lift)|\(s.date)") else { continue }
                    inputs.append(.init(lift: lift, date: s.date, reps: x.kind == .reps ? x.reps : nil,
                                        weightKg: x.weightKg, durationS: x.kind == .timed ? x.durationS : nil,
                                        source: LiftSeries.loggedSource))
                }
            }
        }
        liftInputs = inputs
    }

    // MARK: - Catalogue + order

    /// Lifts with at least one session, most sessions first (then name).
    public var lifts: [String] {
        let deduped = LiftSeries.dedupe(liftInputs)
        let counts = Dictionary(grouping: deduped) { $0.lift }.mapValues { Set($0.map(\.date)).count }
        return counts.keys.sorted { (counts[$0]!, $1) > (counts[$1]!, $0) }
    }

    /// Every chart the data can draw (the Edit sheet's list), strength then cardio.
    public var catalogue: [ProgressChartID] {
        var ids: [ProgressChartID] = []
        for lift in lifts {
            for m in LiftSeries.metrics(lift: lift, inputs: liftInputs) {
                guard let cm = LiftChartMetric(rawValue: m.rawValue) else { continue }
                ids.append(.lift(key: lift, metric: cm))
            }
        }
        ids += RunChartMetric.allCases.map { ProgressChartID.run($0) }
        ids.append(.vo2max)
        return ids
    }

    /// Shown without a pin: each lift's lead metric (e1RM, or Reps for a bodyweight lift, or
    /// Longest Duration for a timed one), run pace, VO₂ max.
    public var defaults: [ProgressChartID] {
        var ids: [ProgressChartID] = []
        for lift in lifts {
            let ms = LiftSeries.metrics(lift: lift, inputs: liftInputs)
            if let lead = [LiftSeries.Metric.e1rm, .reps, .longestDuration].first(where: ms.contains),
               let cm = LiftChartMetric(rawValue: lead.rawValue) {
                ids.append(.lift(key: lift, metric: cm))
            }
        }
        ids.append(.run(.pace))
        ids.append(.vo2max)
        return ids
    }

    /// Display order over the whole screen: pins (pin order) then the defaults, hidden left out.
    public var shown: [ProgressChartID] {
        let cat = Set(catalogue)
        let pinsAvail = prefs.pinned.filter { cat.contains($0) }
        let pinSet = Set(pinsAvail)
        return ProgressChartSelection.displayOrder(prefs, available: pinsAvail + defaults.filter { !pinSet.contains($0) })
    }

    public var strengthCards: [ProgressCard] { shown.filter(Self.isStrength).map(card) }
    public var cardioCards: [ProgressCard] { shown.filter { !Self.isStrength($0) }.map(card) }

    nonisolated static func isStrength(_ id: ProgressChartID) -> Bool {
        if case .lift = id { return true }
        return false
    }

    // MARK: - Cards

    private var rangeStart: String {
        (try? CalendarMath.addDays(today(), -range.days)) ?? "0000-01-01"
    }

    public func card(_ id: ProgressChartID) -> ProgressCard {
        let from = rangeStart
        let pinned = ProgressChartSelection.isPinned(prefs, id)
        switch id {
        case let .lift(key, metric):
            let m = LiftSeries.Metric(rawValue: metric.rawValue) ?? .e1rm
            let inRange = liftInputs.filter { $0.lift == key && $0.date >= from }
            let bucket = LiftSeries.bucket(rangeDays: range.days)
            let series = LiftSeries.series(lift: key, metric: m, inputs: inRange, bucket: bucket)
            let pts = series.points.compactMap { p in ProgressFormat.date(p.date).map { TrendPoint(date: $0, value: p.value) } }
            let caption = [ProgressFormat.metricCaption(m), StrengthRecordsFormat.rangeName(range),
                           bucket == .week ? (m.isSum ? "sum per week" : "heaviest session per week") : nil,
                           sourceLabel(lift: key)].compactMap { $0 }.joined(separator: " · ")
            return ProgressCard(id: id, section: .strength,
                                title: "\(StrengthRecordsFormat.liftTitle(key)) · \(ProgressFormat.metricName(metric))",
                                points: pts, unit: ProgressFormat.unit(id), kind: m.isSum ? .sum : .baseline,
                                count: series.sessionCount, pinned: pinned, caption: caption)
        case let .run(metric):
            let runs = (cardio?.runs ?? []).filter { $0.date >= from }
            let pts: [TrendPoint] = runs.compactMap { r in
                guard let d = ProgressFormat.date(r.date) else { return nil }
                let v: Double? = switch metric {
                case .pace: r.paceSecPerKm
                case .hr: r.avgHr.map(Double.init)
                case .distance: r.distanceM / 1000
                case .duration: Double(r.durationSec) / 60
                }
                return v.map { TrendPoint(date: d, value: $0) }
            }
            return ProgressCard(id: id, section: .cardio, title: "Runs · \(ProgressFormat.runName(metric))", points: pts,
                                unit: ProgressFormat.unit(id), kind: metric == .distance ? .sum : .baseline,
                                count: pts.count, pinned: pinned,
                                caption: "\(ProgressFormat.runCaption(metric)) · \(StrengthRecordsFormat.rangeName(range)) · runs ≥ 1\u{202F}km")
        case .vo2max:
            // RG-11 / B-126: Garmin (~40) and Apple (~25) estimate on different scales — never one line.
            let readings = (cardio?.vo2max ?? []).filter { $0.date >= from }
                .compactMap { v in ProgressFormat.date(v.date).map { (point: TrendPoint(date: $0, value: v.vo2max), source: v.source) } }
                .sorted { $0.point.date < $1.point.date }
            let pts = readings.map(\.point)
            var names: [String] = []
            for r in readings where !names.contains(ProgressFormat.vo2SourceName(r.source)) {
                names.append(ProgressFormat.vo2SourceName(r.source))
            }
            let series = names.map { n in
                TrendSeries(name: n, points: readings.filter { ProgressFormat.vo2SourceName($0.source) == n }.map(\.point),
                            dashed: n != ProgressFormat.vo2SourceName("apple"))
            }
            let sources = names.joined(separator: " + ")
            return ProgressCard(id: id, section: .cardio, title: "VO₂ max", points: pts, unit: ProgressFormat.unit(id),
                                kind: .baseline, count: pts.count, pinned: pinned,
                                caption: "VO₂ max · \(StrengthRecordsFormat.rangeName(range)) · \(sources.isEmpty ? "watch estimate" : sources)"
                                    + (series.count > 1 ? " · one line per source" : ""),
                                series: series, headlineSource: readings.last.map { ProgressFormat.vo2SourceName($0.source) })
        }
    }

    private func sourceLabel(lift: String) -> String {
        let sources = Set(liftInputs.filter { $0.lift == lift }.map(\.source))
        if sources.contains("garmin") { return sources.contains(LiftSeries.loggedSource) ? "Garmin + JI log" : "Garmin" }
        return "JI log"
    }

    /// "4 pinned · Strength + Cardio"
    public var subtitle: String {
        let n = prefs.pinned.filter { Set(catalogue).contains($0) }.count
        return (n == 0 ? "Nothing pinned" : "\(n) pinned") + " · Strength + Cardio"
    }

    // MARK: - Edit (write through on every change)

    public func togglePin(_ id: ProgressChartID) {
        apply(ProgressChartSelection.isPinned(prefs, id) ? ProgressChartSelection.unpin(prefs, id) : ProgressChartSelection.pin(prefs, id))
    }

    public func pin(_ id: ProgressChartID) { apply(ProgressChartSelection.pin(prefs, id)) }
    public func unpin(_ id: ProgressChartID) { apply(ProgressChartSelection.unpin(prefs, id)) }
    public func setHidden(_ id: ProgressChartID, _ hidden: Bool) { apply(ProgressChartSelection.setHidden(prefs, id, hidden: hidden)) }
    public func movePins(fromOffsets source: IndexSet, toOffset destination: Int) {
        apply(ProgressChartSelection.move(prefs, fromOffsets: source, toOffset: destination))
    }
    public func move(_ id: ProgressChartID, direction: Int) { apply(ProgressChartSelection.move(prefs, id, direction: direction)) }

    /// Back to the default (nothing pinned or hidden).
    public func resetPrefs() { apply(ProgressChartSelection.defaultPrefs()) }

    public func isHidden(_ id: ProgressChartID) -> Bool { prefs.hidden.contains(id) }

    private func apply(_ next: ProgressChartPrefs) {
        guard next != prefs else { return }
        prefs = next
        try? prefStore?.set(ProgressChartSelection.prefKey, prefs)
    }

    private func loadPrefs() {
        let raw = (try? prefStore?.get(ProgressChartSelection.prefKey, as: ProgressChartPrefs.self)) ?? nil
        prefs = ProgressChartSelection.reconcile(raw ?? (prefStore == nil ? prefs : nil))
    }

    /// Fixture seams for tests / previews.
    func setHub(_ out: StrengthRecordsOut) { hub = out; recomputeLifts() }
    func setCardio(_ c: CardioSeries) { cardio = c }
}

extension ProgressViewModel: Hashable {
    public nonisolated static func == (a: ProgressViewModel, b: ProgressViewModel) -> Bool { a === b }
    public nonisolated func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }
}

/// B-94 b94p4 — Progress text (pure). Numbers group with U+202F (narrow no-break space) and a
/// value never breaks from its unit.
public nonisolated enum ProgressFormat {
    public static let nnbsp = "\u{202F}"

    private static let iso: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
    public static func date(_ s: String) -> Date? { iso.date(from: String(s.prefix(10))) }

    /// 1350 → "1 350" (U+202F), fractionDigits after the point.
    public static func grouped(_ v: Double, fractionDigits: Int = 0) -> String {
        let neg = v < 0
        let s = String(format: "%.\(fractionDigits)f", abs(v))
        let parts = s.split(separator: ".", maxSplits: 1)
        var intPart = String(parts[0])
        var out = ""
        while intPart.count > 3 {
            out = nnbsp + String(intPart.suffix(3)) + out
            intPart = String(intPart.dropLast(3))
        }
        out = intPart + out
        if parts.count > 1 { out += "." + parts[1] }
        return (neg ? "−" : "") + out
    }

    /// "7:55" from seconds per km.
    public static func pace(_ secPerKm: Double) -> String {
        let t = Int(secPerKm.rounded())
        return "\(t / 60):" + String(format: "%02d", t % 60)
    }

    /// RG-33: how the chart's y-axis ticks and "avg" rule print a value — m:ss for run pace
    /// (raw seconds per km read as "1 000" / "avg 623"); nil = the chart's plain number.
    public static func chartValueFormat(_ id: ProgressChartID) -> (@Sendable (Double) -> String)? {
        if case .run(.pace) = id { return { pace($0) } }
        return nil
    }

    public static func value(_ v: Double, metric id: ProgressChartID) -> String {
        let u = unit(id)
        let n: String
        switch id {
        case let .lift(_, m):
            switch m {
            case .e1rm, .heaviest: n = grouped(v, fractionDigits: v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)
            case .volume, .sets, .reps, .longestDuration: n = grouped(v)
            }
        case let .run(m):
            switch m {
            case .pace: n = pace(v)
            case .hr: n = grouped(v)
            case .distance: n = grouped(v, fractionDigits: 1)
            case .duration: n = grouped(v)
            }
        case .vo2max: n = grouped(v, fractionDigits: 1)
        }
        return u.isEmpty ? n : n + nnbsp + u
    }

    /// RG-11: "apple" → "Apple" (solid line); "garmin" → "Garmin est." (dashed — Garmin's own estimate).
    public static func vo2SourceName(_ source: String) -> String {
        switch source.lowercased() {
        case "apple": "Apple"
        case "garmin": "Garmin est."
        default: source.capitalized
        }
    }

    public static func unit(_ id: ProgressChartID) -> String {
        switch id {
        case let .lift(_, m):
            switch m { case .e1rm, .heaviest, .volume: "kg"; case .sets: "sets"; case .reps: "reps"; case .longestDuration: "s" }
        case let .run(m):
            switch m { case .pace: "/km"; case .hr: "bpm"; case .distance: "km"; case .duration: "min" }
        case .vo2max: ""
        }
    }

    public static func metricName(_ m: LiftChartMetric) -> String {
        switch m {
        case .e1rm: "Est. 1RM"; case .heaviest: "Heaviest"; case .volume: "Volume"
        case .sets: "Sets"; case .reps: "Reps"; case .longestDuration: "Longest hold"
        }
    }

    public static func runName(_ m: RunChartMetric) -> String {
        switch m { case .pace: "Pace"; case .hr: "Avg heart rate"; case .distance: "Distance"; case .duration: "Duration" }
    }

    static func metricCaption(_ m: LiftSeries.Metric) -> String {
        switch m {
        case .e1rm: "Est. 1RM (Epley)"
        case .heaviest: "Heaviest set"
        case .volume: "Volume = Σ reps × kg"
        case .sets: "Sets"
        case .reps: "Reps"
        case .longestDuration: "Longest timed set"
        }
    }

    static func runCaption(_ m: RunChartMetric) -> String {
        switch m { case .pace: "Pace per run (lower is faster)"; case .hr: "Average heart rate per run"
        case .distance: "Distance per run"; case .duration: "Duration per run" }
    }

    /// Name shown in the Edit sheet and the menu.
    public static func title(_ id: ProgressChartID) -> String {
        switch id {
        case let .lift(key, m): "\(StrengthRecordsFormat.liftTitle(key)) · \(metricName(m))"
        case let .run(m): "Runs · \(runName(m))"
        case .vo2max: "VO₂ max"
        }
    }
}
