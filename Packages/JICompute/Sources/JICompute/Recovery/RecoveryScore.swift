import Foundation

/// B-57 W3 — recovery score 0–100. Port of `app/vitals/recovery_score.py` `recovery_score`,
/// golden-tested bit-for-bit (`recovery.golden.json`, 1e-9 on doubles, exact on score/status).
/// CONVENTION (not a finding): equal weights and the linear 0–100 map — no vendor or paper publishes
/// fusion weights. The gate's copy lives in `scripts/morning_go.py`; this one is for display.
/// Missing data is never invented: no HRV tonight = `.missing`, under 14 nights = `.calibrating`.
public nonisolated struct RecoverySeriesDay: Hashable, Sendable, Codable {
    public var date: String
    public var hrvMs, rhrBpm, sleepH, deepH, remH, loadMin: Double?
    /// W-ONDEVICE O-3 (W-CAL C-1): which device the night's HRV came from; nil = untagged / no
    /// HRV. Not scored — the merge sets it, the UI may show it.
    public var source: HrvNightSource?
    public init(date: String, hrvMs: Double? = nil, rhrBpm: Double? = nil, sleepH: Double? = nil,
                deepH: Double? = nil, remH: Double? = nil, loadMin: Double? = nil, source: HrvNightSource? = nil) {
        self.date = date; self.hrvMs = hrvMs; self.rhrBpm = rhrBpm; self.sleepH = sleepH
        self.deepH = deepH; self.remH = remH; self.loadMin = loadMin; self.source = source
    }
}

public nonisolated enum RecoveryComponentKey: String, Sendable, Hashable, CaseIterable { case hrv, rhr, sleep, load }
public nonisolated enum RecoveryComponentStatus: String, Sendable, Hashable { case ok, noReading = "no_reading", calibrating, flat }
public nonisolated enum RecoveryScoreStatus: String, Sendable, Hashable { case ok, calibrating, missing }

public nonisolated struct RecoveryComponent: Hashable, Sendable {
    public let key: RecoveryComponentKey
    public let status: RecoveryComponentStatus
    /// Display value: HRV ms (7-day), RHR bpm, sleep h, load min (7-day).
    public let value: Double?
    /// Clipped to ±3, sign-flipped so higher is always better.
    public let z: Double?
    public let normalN: Int

    public init(key: RecoveryComponentKey, status: RecoveryComponentStatus, value: Double?, z: Double?, normalN: Int) {
        self.key = key; self.status = status; self.value = value; self.z = z; self.normalN = normalN
    }
}

public nonisolated struct RecoveryScoreResult: Hashable, Sendable {
    public let status: RecoveryScoreStatus
    public let score: Int?
    public let raw: Double?
    public let components: [RecoveryComponent]
    public let nights: Int
    public let nightsNeeded: Int
    /// W-CAL C-1: HRV nights in the 28-day normal window by device (display only).
    public let nApple: Int
    public let nGarmin: Int

    public init(status: RecoveryScoreStatus, score: Int?, raw: Double?, components: [RecoveryComponent],
                nights: Int, nightsNeeded: Int = PersonalNormal.minN, nApple: Int = 0, nGarmin: Int = 0) {
        self.status = status; self.score = score; self.raw = raw; self.components = components
        self.nights = nights; self.nightsNeeded = nightsNeeded; self.nApple = nApple; self.nGarmin = nGarmin
    }

    public func component(_ key: RecoveryComponentKey) -> RecoveryComponent? { components.first { $0.key == key } }
}

public nonisolated enum RecoveryScore {
    public static let lowScore = 35
    public static let zCap = 3.0
    public static let loadMinNormalN = 28
    public static let loadMinDaysInWeek = 4

    /// Half-up, identical to Python `int(math.floor(raw + 0.5))`.
    public static func roundScore(_ raw: Double) -> Int { Int((raw + 0.5).rounded(.down)) }

    /// 7-day load ending `end` (ascending dates); nil with fewer than 4 days of data.
    public static func load7(_ daily: [String: Double], end: String) throws -> Double? {
        var total = 0.0
        var n = 0
        for k in stride(from: PersonalNormal.windowDays - 1, through: 0, by: -1) {
            if let v = daily[try CalendarMath.addDays(end, -k)], v.isFinite { total += v; n += 1 }
        }
        return n >= loadMinDaysInWeek ? total : nil
    }

    private static func clipZ(_ x: Double, _ normal: PersonalNormalResult, _ sign: Double) -> Double {
        let z = sign * (x - normal.median) / normal.sd
        return max(-zCap, min(zCap, z))
    }

    private static func component(_ key: RecoveryComponentKey, x: Double?, normal: PersonalNormalResult?,
                                  count: Int, sign: Double, value: Double?) -> RecoveryComponent {
        guard let normal else { return RecoveryComponent(key: key, status: .calibrating, value: value, z: nil, normalN: count) }
        guard let x else { return RecoveryComponent(key: key, status: .noReading, value: nil, z: nil, normalN: count) }
        guard normal.sd > 0 else { return RecoveryComponent(key: key, status: .flat, value: value, z: nil, normalN: count) }
        return RecoveryComponent(key: key, status: .ok, value: value, z: clipZ(x, normal, sign), normalN: count)
    }

    private static func series(_ by: [String: RecoverySeriesDay], _ pick: (RecoverySeriesDay) -> Double?,
                               _ keep: (Double) -> Bool) -> [String: Double] {
        var out: [String: Double] = [:]
        for (k, d) in by { if let v = pick(d), v.isFinite, keep(v) { out[k] = v } }
        return out
    }

    /// W-ONDEVICE O-3 — port of `merge_recovery_days` (@ cal): Apple nights with Garmin filling
    /// the gaps field by field (HRV, RHR, sleep, deep, REM). Only Garmin RMSSD is scaled, by the
    /// one device factor `HrvBand.garminRmssdFactor` unless `factor` is given. Load is never
    /// filled (the loader already picks one device per day). Ascending dates.
    public static func mergeRecoveryDays(apple: [RecoverySeriesDay], garmin: [RecoverySeriesDay],
                                         factor: Double? = nil) -> [RecoverySeriesDay] {
        let f = factor ?? HrvBand.garminRmssdFactor
        var aBy: [String: RecoverySeriesDay] = [:], gBy: [String: RecoverySeriesDay] = [:]
        for d in apple { aBy[d.date] = d }                 // a later duplicate wins, like the Python dict
        for d in garmin { gBy[d.date] = d }
        func finite(_ v: Double?) -> Bool { v?.isFinite == true }
        func pick(_ x: Double?, _ y: Double?) -> Double? { finite(x) ? x : y }
        var out: [RecoverySeriesDay] = []
        for date in Set(aBy.keys).union(gBy.keys).sorted() {
            guard let g = gBy[date] else {
                var a = aBy[date]!
                a.source = finite(a.hrvMs) ? .apple : nil
                out.append(a)
                continue
            }
            let a = aBy[date] ?? RecoverySeriesDay(date: date)
            let hrv: Double?
            let src: HrvNightSource?
            if finite(a.hrvMs) { hrv = a.hrvMs; src = .apple }
            else if finite(g.hrvMs) { hrv = g.hrvMs! * f; src = .garmin }
            else { hrv = nil; src = nil }
            out.append(RecoverySeriesDay(date: date, hrvMs: hrv, rhrBpm: pick(a.rhrBpm, g.rhrBpm),
                                         sleepH: pick(a.sleepH, g.sleepH), deepH: pick(a.deepH, g.deepH),
                                         remH: pick(a.remH, g.remH), loadMin: a.loadMin, source: src))
        }
        return out
    }

    /// Merge (Apple first, Garmin fills) then score — what the hub's recovery loader does.
    public static func compute(apple: [RecoverySeriesDay], garmin: [RecoverySeriesDay], today: String,
                               factor: Double? = nil) throws -> RecoveryScoreResult {
        try compute(days: mergeRecoveryDays(apple: apple, garmin: garmin, factor: factor), today: today)
    }

    public static func compute(days: [RecoverySeriesDay], today: String) throws -> RecoveryScoreResult {
        var by: [String: RecoverySeriesDay] = [:]
        for d in days { by[d.date] = d }                       // a later duplicate wins, like the Python dict
        let hrvLn = series(by, { $0.hrvMs }, { $0 > 0 }).mapValues { Foundation.log($0) }
        let rhr = series(by, { $0.rhrBpm }, { $0 > 0 })
        let sleep = series(by, { $0.sleepH }, { $0 > 0 })
        let deep = series(by, { $0.deepH }, { $0 >= 0 })
        let rem = series(by, { $0.remH }, { $0 >= 0 })
        let dailyLoad = series(by, { $0.loadMin }, { $0 >= 0 })

        // HRV — 7-day rolling mean of ln RMSSD vs the normal of nightly ln RMSSD; tonight must exist.
        let hrvNormal = try PersonalNormal.normal(hrvLn, today: today)
        let hrvX = hrvLn[today] != nil ? try PersonalNormal.windowMean(hrvLn, today: today) : nil
        let hrv = component(.hrv, x: hrvX, normal: hrvNormal, count: try PersonalNormal.count(hrvLn, today: today),
                            sign: 1, value: hrvX.map { Foundation.exp($0) })

        // RHR — last night, lower is better.
        let rhrX = rhr[today]
        let rhrC = component(.rhr, x: rhrX, normal: try PersonalNormal.normal(rhr, today: today),
                             count: try PersonalNormal.count(rhr, today: today), sign: -1, value: rhrX)

        // Sleep — duration / deep / REM each vs its own normal, mean of the available sub-z. No HRV.
        let sleepNormal = try PersonalNormal.normal(sleep, today: today)
        let sleepX = sleep[today]
        let sleepN = try PersonalNormal.count(sleep, today: today)
        let sleepC: RecoveryComponent
        if sleepNormal == nil {
            sleepC = RecoveryComponent(key: .sleep, status: .calibrating, value: sleepX, z: nil, normalN: sleepN)
        } else if sleepX == nil {
            sleepC = RecoveryComponent(key: .sleep, status: .noReading, value: nil, z: nil, normalN: sleepN)
        } else {
            var subs: [Double] = []
            for s in [sleep, deep, rem] {
                guard let x = s[today], let nrm = try PersonalNormal.normal(s, today: today), nrm.sd > 0 else { continue }
                subs.append(clipZ(x, nrm, 1))
            }
            if subs.isEmpty {
                sleepC = RecoveryComponent(key: .sleep, status: .flat, value: sleepX, z: nil, normalN: sleepN)
            } else {
                var total = 0.0
                for z in subs { total += z }
                sleepC = RecoveryComponent(key: .sleep, status: .ok, value: sleepX, z: total / Double(subs.count), normalN: sleepN)
            }
        }

        // Load — 7-day load ending yesterday vs the 28-day normal of 7-day loads; more is worse.
        let (start, _) = try PersonalNormal.window(today: today)
        let yesterday = try CalendarMath.addDays(today, -1)
        var weekly: [String: Double] = [:]
        var d = start
        while d <= yesterday {
            if let v = try load7(dailyLoad, end: d) { weekly[d] = v }
            d = try CalendarMath.addDays(d, 1)
        }
        let loadX = weekly[yesterday]
        let loadC = component(.load, x: loadX, normal: try PersonalNormal.normal(weekly, today: today, minN: loadMinNormalN),
                              count: try PersonalNormal.count(weekly, today: today), sign: -1, value: loadX)

        let comps = [hrv, rhrC, sleepC, loadC]
        let core = [hrv, rhrC, sleepC]
        let nights = core.map(\.normalN).min() ?? 0
        let (nStart, nEnd) = try PersonalNormal.window(today: today)
        let nG = hrvLn.keys.filter { $0 >= nStart && $0 <= nEnd && by[$0]?.source == .garmin }.count
        let nA = try PersonalNormal.count(hrvLn, today: today) - nG
        if core.contains(where: { $0.status == .calibrating }) {
            return RecoveryScoreResult(status: .calibrating, score: nil, raw: nil, components: comps, nights: nights,
                                       nApple: nA, nGarmin: nG)
        }
        guard hrv.z != nil else {
            return RecoveryScoreResult(status: .missing, score: nil, raw: nil, components: comps, nights: nights,
                                       nApple: nA, nGarmin: nG)
        }
        let zs = comps.compactMap(\.z)
        var total = 0.0
        for z in zs { total += z }
        let mean = total / Double(zs.count)
        let raw = max(0.0, min(100.0, 50.0 + mean * 50.0 / 3.0))
        return RecoveryScoreResult(status: .ok, score: roundScore(raw), raw: raw, components: comps, nights: nights,
                                   nApple: nA, nGarmin: nG)
    }
}
