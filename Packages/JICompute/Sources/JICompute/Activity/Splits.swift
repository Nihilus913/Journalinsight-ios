import Foundation

/// W-B98A B98-3 (B-98 5a) — JI-computed km splits from an activity's 1 s sample series.
/// Port of HT `app/training/splits.py` `km_splits` (same rule, same rounding); both reproduce
/// HT `tests/fixtures/splits/{id}_expected.json` (byte copies in Tests/…/Resources/splits).
///
/// Rule: a sample stands until the next one, capped at `maxSampleGapSec` (pauses skipped).
/// Segment distance = speed·dt; haversine between fixes when the segment has no speed but both
/// ends have GPS (Apple route case); 0 otherwise. No speed and no GPS anywhere → [].
/// The 1000 m crossing is interpolated inside its segment (time/HR/elevation split
/// proportionally); a trailing partial km is kept when ≥ `minPartialM`. Pace = s/km; mean HR
/// time-weighted; elevation gain from a centred moving average (`elevSmoothWindow` samples)
/// summing rises — nil without any elevation sample.
/// Display only: "JI-computed, may differ from Garmin"; never auto-claims an interval done.
public nonisolated enum Splits {
    public static let registryKey = "km_splits"
    public static let km = 1000.0
    public static let minPartialM = 50.0
    public static let elevSmoothWindow = 61
    public static let earthRM = 6_371_008.8
    /// Mirrors HT `app/training/completion.py` MAX_SAMPLE_GAP_SEC.
    public static let maxSampleGapSec = 10.0

    public struct Sample: Sendable, Equatable {
        /// Seconds (epoch or offset).
        public let t: Double
        public let hr: Double?
        public let lat: Double?
        public let lon: Double?
        public let elevationM: Double?
        public let speedMps: Double?
        public init(t: Double, hr: Double?, lat: Double?, lon: Double?, elevationM: Double?, speedMps: Double?) {
            self.t = t; self.hr = hr; self.lat = lat; self.lon = lon; self.elevationM = elevationM; self.speedMps = speedMps
        }
        public init(at: Date, hr: Double?, lat: Double?, lon: Double?, elevationM: Double?, speedMps: Double?) {
            self.init(t: at.timeIntervalSince1970, hr: hr, lat: lat, lon: lon, elevationM: elevationM, speedMps: speedMps)
        }
    }

    public struct Split: Sendable, Equatable {
        public let km: Int
        public let distanceM: Double
        public let durationS: Double
        public let paceSPerKm: Double?
        public let meanHr: Double?
        public let elevationGainM: Double?
    }

    public static func haversineM(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = p2 - p1, dl = (lon2 - lon1) * .pi / 180
        let h = pow(sin(dp / 2), 2) + cos(p1) * cos(p2) * pow(sin(dl / 2), 2)
        return 2 * earthRM * asin(sqrt(min(1.0, h)))
    }

    /// Python `round(x, n)`: correctly rounded from the exact binary value, ties to even.
    static func pyRound(_ x: Double, _ n: Int) -> Double {
        Double(String(format: "%.\(n)f", x)) ?? x
    }

    static func smoothedElevation(_ s: [Sample]) -> [Double?] {
        let half = elevSmoothWindow / 2
        return s.indices.map { i in
            guard s[i].elevationM != nil else { return nil }
            let win = s[max(0, i - half)...min(s.count - 1, i + half)].compactMap(\.elevationM)
            return win.reduce(0, +) / Double(win.count)
        }
    }

    static func segmentDistance(_ a: Sample, _ b: Sample, _ d: Double) -> Double {
        if let sp = a.speedMps { return max(0.0, sp) * d }
        if let la = a.lat, let lo = a.lon, let lb = b.lat, let lob = b.lon, d > 0 {
            return haversineM(la, lo, lb, lob)
        }
        return 0.0
    }

    struct Bucket {
        var dist = 0.0, dur = 0.0, hrS = 0.0, hrW = 0.0, gain = 0.0
        var hasElev = false

        mutating func add(_ dist: Double, _ dur: Double, _ hr: Double?, _ rise: Double?) {
            self.dist += dist
            self.dur += dur
            if let hr, dur > 0 { hrS += hr * dur; hrW += dur }
            if let rise { hasElev = true; gain += max(0.0, rise) }
        }

        func out(_ km: Int) -> Split {
            Split(
                km: km,
                distanceM: pyRound(dist, 2),
                durationS: pyRound(dur, 2),
                paceSPerKm: dist > 0 ? pyRound(dur / dist * Splits.km, 2) : nil,
                meanHr: hrW > 0 ? pyRound(hrS / hrW, 1) : nil,
                elevationGainM: hasElev ? pyRound(gain, 1) : nil
            )
        }
    }

    /// Per-km splits (last one partial); [] when the series has no speed and no GPS distance.
    public static func kmSplits(_ samples: [Sample]) -> [Split] {
        let pts = samples
        guard pts.count >= 2 else { return [] }
        let hasSpeed = pts.contains { $0.speedMps != nil }
        let hasGps = pts.contains { $0.lat != nil && $0.lon != nil }
        guard hasSpeed || hasGps else { return [] }
        let elev = smoothedElevation(pts)
        var out: [Split] = []
        var cur = Bucket()
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            let raw = b.t - a.t
            if raw <= 0 { continue }
            let d = min(raw, maxSampleGapSec)
            let dist = (raw <= maxSampleGapSec || a.speedMps != nil) ? segmentDistance(a, b, d) : 0.0
            let rise: Double? = (elev[i] != nil && elev[i + 1] != nil) ? elev[i + 1]! - elev[i]! : nil
            let hr = a.hr
            var fracLeft = 1.0
            while dist * fracLeft > 0 && cur.dist + dist * fracLeft >= km {
                let need = km - cur.dist
                let f = need / dist
                cur.add(need, d * f, hr, rise.map { $0 * f })
                out.append(cur.out(out.count + 1))
                cur = Bucket()
                fracLeft -= f
            }
            if fracLeft > 0 {
                cur.add(dist * fracLeft, d * fracLeft, hr, rise.map { $0 * fracLeft })
            }
        }
        if cur.dist >= minPartialM { out.append(cur.out(out.count + 1)) }
        return out
    }
}
