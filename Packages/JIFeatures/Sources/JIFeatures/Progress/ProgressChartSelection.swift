import Foundation

/// B-94 p1 — metric shown by a per-lift progress chart.
public nonisolated enum LiftChartMetric: String, Codable, Sendable, CaseIterable {
    case e1rm, heaviest, volume, sets, reps, longestDuration
}

/// B-94 p1 — metric shown by a run progress chart.
public nonisolated enum RunChartMetric: String, Codable, Sendable, CaseIterable {
    case pace, hr, distance, duration
}

/// B-94 p1 — one chart on the Progress screen. `key` of `.lift` is the lift's plan name
/// (`ExerciseAliases.byPlanName` key, e.g. "Barbell Bench Press").
///
/// Persisted as a flat string (`rawValue`): "lift:<key>:<metric>", "run:<metric>", "vo2max" —
/// so an id whose metric/case a later build drops decodes as `nil` (stale) instead of failing
/// the whole prefs blob.
public nonisolated enum ProgressChartID: Hashable, Sendable, Codable, CustomStringConvertible {
    case lift(key: String, metric: LiftChartMetric)
    case run(RunChartMetric)
    case vo2max

    public var rawValue: String {
        switch self {
        case let .lift(key, metric): return "lift:\(key):\(metric.rawValue)"
        case let .run(metric): return "run:\(metric.rawValue)"
        case .vo2max: return "vo2max"
        }
    }

    public var description: String { rawValue }

    /// `nil` for anything this build does not know (unknown kind/metric, empty lift key).
    public init?(rawValue: String) {
        if rawValue == "vo2max" { self = .vo2max; return }
        if rawValue.hasPrefix("run:") {
            guard let m = RunChartMetric(rawValue: String(rawValue.dropFirst(4))) else { return nil }
            self = .run(m); return
        }
        if rawValue.hasPrefix("lift:") {
            let rest = rawValue.dropFirst(5)
            // Metric is after the LAST ':' so a lift name containing ':' still round-trips.
            guard let sep = rest.lastIndex(of: ":") else { return nil }
            let key = String(rest[rest.startIndex..<sep])
            guard !key.isEmpty, let m = LiftChartMetric(rawValue: String(rest[rest.index(after: sep)...])) else { return nil }
            self = .lift(key: key, metric: m); return
        }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let id = ProgressChartID(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown ProgressChartID \(raw)"))
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// B-94 p1 — pinned (ordered, 0..N) and hidden charts. Local only (`PrefStore`, no sync).
public nonisolated struct ProgressChartPrefs: Codable, Sendable, Equatable {
    /// Pinned charts in display order, first = top.
    public var pinned: [ProgressChartID]
    /// Charts hidden from the Progress screen (never also pinned).
    public var hidden: [ProgressChartID]

    public init(pinned: [ProgressChartID] = [], hidden: [ProgressChartID] = []) {
        self.pinned = pinned; self.hidden = hidden
    }

    private enum CodingKeys: String, CodingKey { case pinned, hidden }

    /// Lenient: unknown/stale id strings are dropped, a missing key reads as empty.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func ids(_ k: CodingKeys) throws -> [ProgressChartID] {
            (try c.decodeIfPresent([String].self, forKey: k) ?? []).compactMap(ProgressChartID.init(rawValue:))
        }
        self.pinned = try ids(.pinned)
        self.hidden = try ids(.hidden)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pinned.map(\.rawValue), forKey: .pinned)
        try c.encode(hidden.map(\.rawValue), forKey: .hidden)
    }
}

/// B-94 p1 — pure edit operations on `ProgressChartPrefs`, same shape as `KpiSelection`.
/// `PrefStore` read/write is the view model's job (b94p4).
public nonisolated enum ProgressChartSelection {
    public static let prefKey = "progress_charts.prefs.v1"

    /// Default = nothing pinned, nothing hidden.
    public static func defaultPrefs() -> ProgressChartPrefs { ProgressChartPrefs() }

    public static func isPinned(_ prefs: ProgressChartPrefs, _ id: ProgressChartID) -> Bool { prefs.pinned.contains(id) }

    /// Appends `id` to the end of the pins (and un-hides it). Same value if already pinned.
    public static func pin(_ prefs: ProgressChartPrefs, _ id: ProgressChartID) -> ProgressChartPrefs {
        guard !prefs.pinned.contains(id) else { return prefs }
        return ProgressChartPrefs(pinned: prefs.pinned + [id], hidden: prefs.hidden.filter { $0 != id })
    }

    /// Removes `id` from the pins. Same value if not pinned.
    public static func unpin(_ prefs: ProgressChartPrefs, _ id: ProgressChartID) -> ProgressChartPrefs {
        guard prefs.pinned.contains(id) else { return prefs }
        return ProgressChartPrefs(pinned: prefs.pinned.filter { $0 != id }, hidden: prefs.hidden)
    }

    /// Hides `id` (unpinning it) or shows it again. Same value when nothing changes.
    public static func setHidden(_ prefs: ProgressChartPrefs, _ id: ProgressChartID, hidden: Bool) -> ProgressChartPrefs {
        if hidden {
            guard !prefs.hidden.contains(id) else { return prefs }
            return ProgressChartPrefs(pinned: prefs.pinned.filter { $0 != id }, hidden: prefs.hidden + [id])
        }
        guard prefs.hidden.contains(id) else { return prefs }
        return ProgressChartPrefs(pinned: prefs.pinned, hidden: prefs.hidden.filter { $0 != id })
    }

    /// Moves pinned `id` one slot earlier (-1) or later (+1). Same value at either end or when
    /// `id` is not pinned.
    public static func move(_ prefs: ProgressChartPrefs, _ id: ProgressChartID, direction: Int) -> ProgressChartPrefs {
        guard let idx = prefs.pinned.firstIndex(of: id) else { return prefs }
        let to = idx + direction
        guard prefs.pinned.indices.contains(to) else { return prefs }
        var pinned = prefs.pinned
        pinned.swapAt(idx, to)
        return ProgressChartPrefs(pinned: pinned, hidden: prefs.hidden)
    }

    /// SwiftUI `List.onMove` semantics (`destination` is the insert index before removal).
    public static func move(_ prefs: ProgressChartPrefs, fromOffsets source: IndexSet, toOffset destination: Int) -> ProgressChartPrefs {
        guard !source.isEmpty, source.allSatisfy({ prefs.pinned.indices.contains($0) }),
              (0...prefs.pinned.count).contains(destination) else { return prefs }
        let moving = source.map { prefs.pinned[$0] }
        var rest: [ProgressChartID] = []
        var insertAt = destination
        for (i, id) in prefs.pinned.enumerated() {
            if source.contains(i) { if i < destination { insertAt -= 1 } } else { rest.append(id) }
        }
        rest.insert(contentsOf: moving, at: insertAt)
        return ProgressChartPrefs(pinned: rest, hidden: prefs.hidden)
    }

    /// Normalizes a persisted (possibly nil/legacy) blob: drops duplicates, drops a hidden id
    /// that is also pinned (pin wins), and — when `available` is given — drops any id no longer
    /// offered (a lift with no sessions left, a removed metric). Pin order is kept.
    public static func reconcile(_ raw: ProgressChartPrefs?, available: Set<ProgressChartID>? = nil) -> ProgressChartPrefs {
        guard let raw else { return defaultPrefs() }
        func keep(_ id: ProgressChartID) -> Bool { available?.contains(id) ?? true }
        var seen = Set<ProgressChartID>()
        let pinned = raw.pinned.filter { keep($0) && seen.insert($0).inserted }
        let hidden = raw.hidden.filter { keep($0) && seen.insert($0).inserted }
        return ProgressChartPrefs(pinned: pinned, hidden: hidden)
    }

    /// Display order for the charts in `available`: pins first (pin order), then the rest in
    /// `available` order; hidden ids are left out.
    public static func displayOrder(_ prefs: ProgressChartPrefs, available: [ProgressChartID]) -> [ProgressChartID] {
        let avail = Set(available)
        let hidden = Set(prefs.hidden)
        let pins = prefs.pinned.filter { avail.contains($0) }
        let pinSet = Set(pins)
        return pins + available.filter { !pinSet.contains($0) && !hidden.contains($0) }
    }
}
