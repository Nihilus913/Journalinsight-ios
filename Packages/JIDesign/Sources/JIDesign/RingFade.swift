import SwiftUI

/// B-33 §4 fade: piecewise-linear through (0, 0), (⅓, 0.12), (⅔, 0.45), (1, 1) — the fill only
/// saturates over its last third. Shared by the readiness arc, `ScoreRing` and `MacroRings`.
public nonisolated func ringFadeOpacity(at t: Double) -> Double {
    let x = min(1, max(0, t))
    let knots: [(x: Double, y: Double)] = [(0, 0), (1.0 / 3, 0.12), (2.0 / 3, 0.45), (1, 1)]
    for i in 1..<knots.count where x <= knots[i].x {
        let (x0, y0) = knots[i - 1], (x1, y1) = knots[i]
        return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    }
    return 1
}

/// Gradient stops for an `AngularGradient` that runs from the arc's start (location 0) to its
/// head (location 1).
public nonisolated func ringFadeStops(_ tint: Color, samples: Int = 24) -> [Gradient.Stop] {
    (0...samples).map { i in
        let t = Double(i) / Double(samples)
        return Gradient.Stop(color: tint.opacity(ringFadeOpacity(at: t)), location: t)
    }
}

/// value / max clamped to 0…1; a non-positive max is an empty ring (never a division by zero).
public nonisolated func ringFraction(value: Double, max: Double) -> Double {
    guard max > 0 else { return 0 }
    return min(1, Swift.max(0, value / max))
}

/// "<n> of <max>" — the VoiceOver value of every ring (§4b).
public nonisolated func ringAccessibilityValue(value: Double, max: Double) -> String {
    "\(value.formatted(.number.precision(.fractionLength(0)))) of \(max.formatted(.number.precision(.fractionLength(0))))"
}
