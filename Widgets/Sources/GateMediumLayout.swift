import CoreGraphics

/// W-FIX5 W5-1: the medium gate widget's columns. The call column keeps at least `leftMin`; the
/// signal columns share the rest, each at most `signalMax`; whatever the signals leave goes back to
/// the call. Pure and in its own file, so AppTests compile it (GateWidget.swift needs the whole extension).
nonisolated enum GateMediumLayout {
    static let spacing: CGFloat = 12
    static let signalSpacing: CGFloat = 6
    static let leftMin: CGFloat = 104
    static let signalMax: CGFloat = 56

    static func columns(width: CGFloat, signalCount: Int) -> (left: CGFloat, signal: CGFloat) {
        let w = max(0, width)
        guard signalCount > 0 else { return (w, 0) }
        let n = CGFloat(signalCount)
        let gaps = spacing + (n - 1) * signalSpacing
        let signal = max(0, min(signalMax, (w - leftMin - gaps) / n))
        return (max(0, w - gaps - n * signal), signal)
    }
}
