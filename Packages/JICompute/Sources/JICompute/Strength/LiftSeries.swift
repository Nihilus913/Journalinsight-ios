import Foundation

/// B-94 / BP-4 part b94p2 — per-lift progress-chart series (card docs/waves/cards/B-94.md).
/// Pure arithmetic over set rows; the time-series view of `OneRepMax` (B-89):
/// e1RM / heaviest / volume reuse `OneRepMax.histories` so the chart and the records screen
/// never disagree. Sets / Reps are counts of every set, Longest Duration = max `durationS`.
///
/// Rules:
/// - Dedupe: a lift × day logged by both Garmin and JI counts once — the JI log
///   (`source == "logged"`) wins, else the source with most sets.
/// - Bodyweight lift (no set with weight > 0): Sets / Reps only (plus Longest Duration when
///   timed), never e1RM / heaviest / volume.
/// - Weekly bucket (6M / Y): one point per ISO week (date = its Monday). Volume and Sets are
///   the week's sum; every other metric is the value of the week's heaviest session.
/// - `insufficient` when fewer than 3 sessions feed the metric ("Not enough data yet",
///   never a false zero).
public nonisolated enum LiftSeries {
    public static let minSessions = 3
    public static let loggedSource = "logged"

    /// Raw names match `ProgressChartID` lift metrics (b94p1).
    public enum Metric: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
        case e1rm, heaviest, volume, sets, reps, longestDuration
        /// Summed per ISO week; the others take the week's heaviest session.
        public var isSum: Bool { self == .volume || self == .sets }
    }

    public enum Bucket: String, Sendable, Equatable { case session, week }

    /// One set row: lift = plan name (after `ExerciseAliases`), date = "YYYY-MM-DD",
    /// source = "garmin" | "logged".
    public struct Input: Sendable, Equatable {
        public let lift: String, date: String, reps: Int?, weightKg: Double?, durationS: Int?, source: String
        public init(lift: String, date: String, reps: Int?, weightKg: Double?, durationS: Int? = nil, source: String) {
            self.lift = lift; self.date = date; self.reps = reps; self.weightKg = weightKg
            self.durationS = durationS; self.source = source
        }
    }

    /// One deduped lift × day.
    public struct SessionStats: Sendable, Equatable, Identifiable {
        public let date: String
        public let sets: Int, reps: Int
        /// nil when no set counts for B-89 (bodyweight, > 12 reps, under the kg minimum).
        public let e1rm: Double?, heaviestKg: Double?, volumeKg: Double?
        /// nil when the session has no timed set.
        public let longestDurationS: Int?
        public let source: String
        public var id: String { date }

        public func value(_ m: Metric) -> Double? {
            switch m {
            case .e1rm: e1rm
            case .heaviest: heaviestKg
            case .volume: volumeKg
            case .sets: sets > 0 ? Double(sets) : nil
            case .reps: reps > 0 ? Double(reps) : nil
            case .longestDuration: longestDurationS.map(Double.init)
            }
        }

        /// "Heaviest session" order for the weekly bucket: weight, then e1RM, reps, time held.
        var weight: (Double, Double, Int, Int) { (heaviestKg ?? 0, e1rm ?? 0, reps, longestDurationS ?? 0) }
    }

    public struct Point: Sendable, Equatable, Identifiable {
        public let date: String, value: Double
        public var id: String { date }
        public init(date: String, value: Double) { self.date = date; self.value = value }
    }

    public struct Series: Sendable, Equatable {
        public let lift: String, metric: Metric, bucket: Bucket
        /// Oldest first.
        public let points: [Point]
        /// Deduped sessions that carry a value for this metric.
        public let sessionCount: Int
        public var insufficient: Bool { sessionCount < LiftSeries.minSessions }
    }

    /// 6M / Y (≥ 182 days) roll up per ISO week; D / W / M keep one point per session.
    public static func bucket(rangeDays: Int) -> Bucket { rangeDays >= 182 ? .week : .session }

    /// Drops the duplicate source of a lift × day logged twice (Garmin + JI).
    public static func dedupe(_ inputs: [Input]) -> [Input] {
        var bySession: [String: [String: [Input]]] = [:]
        var order: [String] = []
        for i in inputs {
            let k = "\(i.lift)|\(i.date)"
            if bySession[k] == nil { order.append(k) }
            bySession[k, default: [:]][i.source, default: []].append(i)
        }
        return order.flatMap { k -> [Input] in
            let bySource = bySession[k]!
            if let logged = bySource[loggedSource] { return logged }
            let best = bySource.max { ($0.value.count, $1.key) < ($1.value.count, $0.key) }!
            return best.value
        }
    }

    /// Deduped sessions of one lift, oldest first.
    public static func sessions(lift: String, inputs: [Input]) -> [SessionStats] {
        let rows = dedupe(inputs.filter { $0.lift == lift })
        let b89 = OneRepMax.histories(rows.map {
            OneRepMax.Input(lift: $0.lift, date: $0.date, reps: $0.reps, weightKg: $0.weightKg, source: $0.source)
        }).first
        let byDate = Dictionary(uniqueKeysWithValues: (b89?.sessions ?? []).map { ($0.date, $0) })
        let grouped = Dictionary(grouping: rows, by: \.date)
        return grouped.keys.sorted().map { date in
            let sets = grouped[date]!
            let s = byDate[date]
            let durations = sets.compactMap(\.durationS).filter { $0 > 0 }
            return SessionStats(date: date, sets: sets.count, reps: sets.compactMap(\.reps).filter { $0 > 0 }.reduce(0, +),
                                e1rm: s?.e1rm, heaviestKg: s?.heaviestKg, volumeKg: s?.volumeKg,
                                longestDurationS: durations.max(), source: sets[0].source)
        }
    }

    /// Bodyweight = no set of the lift ever carried weight.
    public static func isBodyweight(lift: String, inputs: [Input]) -> Bool {
        !inputs.contains { $0.lift == lift && ($0.weightKg ?? 0) > 0 }
    }

    /// Charts this lift can show, in `Metric` order.
    public static func metrics(lift: String, inputs: [Input]) -> [Metric] {
        let ss = sessions(lift: lift, inputs: inputs)
        let bodyweight = isBodyweight(lift: lift, inputs: inputs)
        return Metric.allCases.filter { m in
            if bodyweight, [.e1rm, .heaviest, .volume].contains(m) { return false }
            return ss.contains { $0.value(m) != nil }
        }
    }

    public static func series(lift: String, metric: Metric, inputs: [Input], bucket: Bucket = .session) -> Series {
        let bodyweight = isBodyweight(lift: lift, inputs: inputs)
        let weightedOnly: Set<Metric> = [.e1rm, .heaviest, .volume]
        let ss = (bodyweight && weightedOnly.contains(metric)) ? [] :
            sessions(lift: lift, inputs: inputs).filter { $0.value(metric) != nil }
        let points: [Point]
        switch bucket {
        case .session:
            points = ss.map { Point(date: $0.date, value: $0.value(metric)!) }
        case .week:
            let weeks = Dictionary(grouping: ss) { isoWeekMonday($0.date) }
            points = weeks.keys.sorted().map { monday in
                let wk = weeks[monday]!
                if metric.isSum {
                    return Point(date: monday, value: OneRepMax.round1(wk.reduce(0) { $0 + $1.value(metric)! }))
                }
                let top = wk.max { $0.weight < $1.weight || ($0.weight == $1.weight && $0.date < $1.date) }!
                return Point(date: monday, value: top.value(metric)!)
            }
        }
        return Series(lift: lift, metric: metric, bucket: bucket, points: points, sessionCount: ss.count)
    }

    /// Monday ("YYYY-MM-DD") of the ISO week holding `iso`.
    public static func isoWeekMonday(_ iso: String) -> String {
        var cal = Calendar(identifier: .iso8601); cal.timeZone = TimeZone(identifier: "UTC")!
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso),
              let start = cal.dateInterval(of: .weekOfYear, for: d)?.start else { return iso }
        return f.string(from: start)
    }
}
