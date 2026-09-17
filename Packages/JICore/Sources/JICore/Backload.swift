import Foundation

// W2h frozen contract: the HealthKit backloader (JIHealthKit) implements `BackloadRunning`;
// the Settings UI (JIFeatures) drives it through the protocol only. Neither side edits this file.

/// Inclusive day range to backload, hub-local dates (Europe/Zurich).
public struct BackloadRange: Sendable, Equatable {
    public var from: Date
    public var to: Date
    public init(from: Date, to: Date) { self.from = from; self.to = to }
}

/// Emitted after every month chunk.
public struct BackloadProgress: Sendable, Equatable {
    public var monthIndex: Int      // 1-based
    public var monthCount: Int
    public var written: Int         // samples saved so far
    public var skipped: Int         // already present (same sync id) so far
    public init(monthIndex: Int, monthCount: Int, written: Int, skipped: Int) {
        self.monthIndex = monthIndex; self.monthCount = monthCount; self.written = written; self.skipped = skipped
    }
}

public struct BackloadSummary: Sendable, Equatable {
    public var written: Int
    public var skipped: Int
    public var failed: [String]     // sync ids the store rejected
    public init(written: Int, skipped: Int, failed: [String]) {
        self.written = written; self.skipped = skipped; self.failed = failed
    }
}

public enum BackloadError: Error, Sendable, Equatable {
    case healthDataUnavailable
    case authorizationDenied
    case hub(String)
}

public protocol BackloadRunning: Sendable {
    /// Requests HealthKit share authorization for every written type; throws `.authorizationDenied`.
    func authorize() async throws
    /// Writes the range month by month, resuming from the persisted cursor; idempotent by sync id.
    func run(_ range: BackloadRange, progress: @Sendable (BackloadProgress) -> Void) async throws -> BackloadSummary
}
