import Foundation
import os

// W8-L1 (P-haptics). Port of `haptics.ts`'s `logHapticMarker` (E22-3): one log line per haptic
// TRIGGER instant, correlated by `feelgate.py`'s `check_haptic_sync` against its visual-change
// measurement. Format FROZEN byte-for-byte (CONTEXT-E24-HAPTICS §2d):
//
//     [FEELGATE_HAPTIC] <label> t=<epoch ms>
//
// Fires BEFORE the native call (its timestamp is as close as we get to "app decided to haptic")
// and independent of the call's outcome. Deliberately NOT debug-gated: feel is measured on the
// RELEASE build (house lesson #1). Pure line builder + a swappable sink: `nonisolated`.

public nonisolated enum JIFeelgateMarker {
    public static let prefix = "[FEELGATE_HAPTIC]"

    /// The frozen line. `timestampMs` is device wall-clock epoch ms (RN `Date.now()`), which
    /// feelgate.py's host<->device clock-skew correction expects.
    public static func line(label: String, timestampMs: Int64) -> String {
        "\(prefix) \(label) t=\(timestampMs)"
    }

    /// Epoch ms now — the one `Date()` read the marker makes.
    public static func nowMs() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)) }

    /// Parses a marker line back (feelgate.py's own regex `^\[FEELGATE_HAPTIC\] (\S+) t=(\d+)$`);
    /// nil when the line is not a marker.
    public static func parse(_ line: String) -> (label: String, timestampMs: Int64)? {
        guard let match = line.wholeMatch(of: /^\[FEELGATE_HAPTIC\] (\S+) t=(\d+)$/),
              let ms = Int64(match.output.2) else { return nil }
        return (String(match.output.1), ms)
    }

    /// Where lines go by default: the unified log (`os.Logger`, subsystem `toby913.JournalInsight`,
    /// category `feelgate`) at `.default` level, so `log stream --predicate 'category == "feelgate"'`
    /// sees it on a RELEASE build — the iOS equivalent of RN's un-stripped `console.log`.
    /// `JIHapticDispatcher.marker` is the per-dispatcher seam tests capture through (RN
    /// `jest.spyOn(console, "log")`); production dispatchers point it here.
    public typealias Sink = @Sendable (String) -> Void
    private static let logger = Logger(subsystem: "toby913.JournalInsight", category: "feelgate")
    public static let unifiedLogSink: Sink = { line in Self.logger.log("\(line, privacy: .public)") }

    /// `logHapticMarker(label)` — builds the line with `timestampMs` and hands it to `sink`.
    public static func log(label: String, timestampMs: Int64, to sink: Sink = unifiedLogSink) {
        sink(line(label: label, timestampMs: timestampMs))
    }
}
