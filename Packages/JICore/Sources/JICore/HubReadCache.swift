import Foundation
import Synchronization

/// B-52 p1 (b): the store every hub GET goes through by default (`HubClient.get`). A successful
/// read writes its raw response bytes under `HubReadKey.make(path:query:)`; a read that fails
/// because the hub is unreachable answers from the last stored bytes instead and is recorded as
/// STALE in `HubReadStaleness.shared` (never a blank screen, never a fabricated value — a key
/// that was never read stays a thrown error, so a cold cache is still an honest empty state).
///
/// Lives in JICore (not JIPersistence) so JIHub can depend on the protocol without pulling GRDB
/// into the Watch; `OfflineCache` (JIPersistence) is the production conformance.
public protocol HubReadCache: Sendable {
    /// The bytes and fetch time last stored under `key`, or nil (never read / unreadable).
    func loadRead(_ key: String) -> (data: Data, fetchedAt: Date)?
    /// Stores a fresh successful read. Best effort: a failed write must never fail the read.
    func storeRead(_ key: String, _ data: Data)
}

public enum HubReadKey {
    /// One key per route + args: "hub:GET <path>?<k=v&…>" with the query sorted, so the same read
    /// with the same args always lands on one row whatever order the caller built the dictionary in.
    public static func make(path: String, query: [String: String] = [:]) -> String {
        guard !query.isEmpty else { return "hub:GET \(path)" }
        let q = query.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        return "hub:GET \(path)?\(q)"
    }
}

/// One hub read with its provenance: `stale == true` means the hub was unreachable and `value`
/// is the copy fetched at `fetchedAt`.
public struct HubRead<T> {
    public let value: T
    public let fetchedAt: Date
    public let stale: Bool
    public init(value: T, fetchedAt: Date, stale: Bool) { self.value = value; self.fetchedAt = fetchedAt; self.stale = stale }
}
extension HubRead: Sendable where T: Sendable {}

/// How a hub GET may use `HubReadCache`, scoped per task (`HubReadPolicy.$current.withValue`).
/// `.cacheFallback` is the default for every read. `.networkOnly` is for a caller that keeps its
/// OWN cache with its own staleness contract (`SectionLoader`): it must see the hub's failure to
/// tag its section stale, not a silently substituted copy.
public enum HubReadPolicy: Sendable {
    case cacheFallback
    case networkOnly
    @TaskLocal public static var current: HubReadPolicy = .cacheFallback
}

/// Collects which reads inside one scope were answered from cache — for a caller that reads through
/// an opaque provider method (`provider.trainingBreak()`) and still wants to say "offline, as of …".
///
///     let (value, staleSince) = try await HubReadTrace.collect { try await provider.trainingBreak() }
public final class HubReadTrace: Sendable {
    @TaskLocal public static var current: HubReadTrace?
    private let served = Mutex<[String: Date]>([:])
    public init() {}
    public func record(_ key: String, fetchedAt: Date) { served.withLock { $0[key] = fetchedAt } }
    /// The OLDEST stale copy served in this scope (nil = every read was fresh).
    public var staleSince: Date? { served.withLock { $0.values.min() } }
    public var staleKeys: [String] { served.withLock { $0.keys.sorted() } }

    public static func collect<T>(_ body: () async throws -> T) async rethrows -> (value: T, staleSince: Date?) {
        let trace = HubReadTrace()
        let value = try await $current.withValue(trace) { try await body() }
        return (value, trace.staleSince)
    }
}

/// Process-wide record of which hub reads were last served from cache (key → fetchedAt of the copy
/// served). A fresh read of the same key clears it. The global offline marker (B-52 p5) and any
/// screen that wants a per-section "offline, as of …" line read it.
public final class HubReadStaleness: Sendable {
    public static let shared = HubReadStaleness()
    private let staleKeys = Mutex<[String: Date]>([:])
    public init() {}

    public func markStale(_ key: String, fetchedAt: Date) { staleKeys.withLock { $0[key] = fetchedAt } }
    public func markFresh(_ key: String) { _ = staleKeys.withLock { $0.removeValue(forKey: key) } }
    /// The fetch time of the stale copy last served for `key`, or nil when its last read was fresh.
    public func staleSince(_ key: String) -> Date? { staleKeys.withLock { $0[key] } }
    public func isStale(path: String, query: [String: String] = [:]) -> Bool {
        staleSince(HubReadKey.make(path: path, query: query)) != nil
    }
    public var anyStale: Bool { staleKeys.withLock { !$0.isEmpty } }
    public var count: Int { staleKeys.withLock { $0.count } }
    public func reset() { staleKeys.withLock { $0.removeAll() } }
}
