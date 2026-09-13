import Foundation
import JICore
import JIPersistence

/// Result of fetching one independently-loadable screen section (PARITY-7): the value actually shown
/// (live, or a cache fallback), the moment it was captured (live fetch time, or the cache's original
/// write time on fallback — `nil` only when there is neither), and the typed hub error from the live
/// attempt when one occurred (`nil` on a clean live success). `stale` marks a cache fallback so a
/// caller can tell a fresh live value from a carried-over one without re-deriving it from `error`.
nonisolated public struct SectionResult<T: Sendable>: Sendable {
    public let value: T?
    public let fetchedAt: Date?
    public let error: HubError?
    public let stale: Bool
}

/// Fetches one screen section independently of its siblings, so a single failing section (a hub route
/// timing out, a decode error) never blanks sections that succeeded — PARITY-7's "not the whole
/// screen". A live failure falls back to whatever `cache` holds for `key`, tagged `stale`; a genuinely
/// empty cache surfaces as a `nil` value with the typed `error` still attached — never silently
/// swallowed (CLAUDE.md rule 4: named hub errors are UI contracts).
///
/// Cancellation is NOT treated as a section failure: it is rethrown as-is so a caller awaiting several
/// sections together (e.g. via `async let`) still observes the cancellation and can return to `.idle`
/// instead of reporting a false error — CODE-1's cancellation contract carries over unchanged.
nonisolated public enum SectionLoader {
    public static func load<T: Codable & Sendable>(
        key: String,
        cache: OfflineCache,
        fetch: () async throws -> T
    ) async throws -> SectionResult<T> {
        do {
            let value = try await fetch()
            try? cache.put(key, value)
            return SectionResult(value: value, fetchedAt: Date(), error: nil, stale: false)
        } catch {
            if Task.isCancelled { throw error }
            let hubError = (error as? HubError) ?? .decoding("\(error)")
            if let hit = try? cache.get(key, as: T.self) {
                return SectionResult(value: hit.value, fetchedAt: hit.fetchedAt, error: hubError, stale: true)
            }
            return SectionResult(value: nil, fetchedAt: nil, error: hubError, stale: false)
        }
    }
}
