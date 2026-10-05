import Foundation
import JICore
import JIPersistence

/// B-52 p1 (a): how a queued row of one outbox `kind` is replayed against the hub. Built once per
/// kind (`OutboxReplayHandler.make`) and registered in `OutboxFirstRegistry.shared` at launch, so
/// EVERY `OutboxDrainer` instance (in-tap, watchdog regain, retry scheduler, BG refresh) can
/// deliver it — a later B-52 part adds a write by registering a handler, never by editing the
/// drainer's switch.
public struct OutboxReplayHandler: Sendable {
    public let kind: String
    /// Last-write-wins grouping: rows of this kind with the same key collapse to the NEWEST one
    /// (sent once; the older ones retire with it). nil = every row is sent, oldest first.
    public let coalesceKey: (@Sendable (Data) -> String?)?
    /// Decodes the stored payload and performs the hub write. Throws to keep the row queued.
    public let replay: @MainActor @Sendable (Data) async throws -> Void
    /// Human line stored as `lastError` when a replay fails.
    public let describe: @Sendable (Error) -> String

    public init(kind: String,
                coalesceKey: (@Sendable (Data) -> String?)? = nil,
                describe: @escaping @Sendable (Error) -> String = OutboxReplayHandler.defaultDescribe,
                replay: @escaping @MainActor @Sendable (Data) async throws -> Void) {
        self.kind = kind; self.coalesceKey = coalesceKey; self.describe = describe; self.replay = replay
    }

    /// Typed builder: the payload is stored with a plain `JSONEncoder` (`Outbox.enqueue`) and
    /// decoded here with the matching plain `JSONDecoder`.
    public static func make<P: Codable & Sendable>(
        kind: String,
        payload: P.Type,
        coalesce: (@Sendable (P) -> String)? = nil,
        describe: @escaping @Sendable (Error) -> String = OutboxReplayHandler.defaultDescribe,
        send: @escaping @MainActor @Sendable (P) async throws -> Void
    ) -> OutboxReplayHandler {
        var key: (@Sendable (Data) -> String?)?
        if let coalesce {
            key = { @Sendable (data: Data) -> String? in
                guard let body = try? JSONDecoder().decode(P.self, from: data) else { return nil }
                return coalesce(body)
            }
        }
        let replay: @MainActor @Sendable (Data) async throws -> Void = { data in
            let body: P
            do { body = try JSONDecoder().decode(P.self, from: data) } catch { throw OutboxFirstError.undecodable(kind) }
            try await send(body)
        }
        return OutboxReplayHandler(kind: kind, coalesceKey: key, describe: describe, replay: replay)
    }

    public nonisolated static func defaultDescribe(_ error: Error) -> String {
        switch error as? HubError {
        case .http(_, let detail) where detail?.isEmpty == false: detail!
        case .network(let message): message
        case .unauthorized: "Hub rejected the token — check Settings › Connection."
        default: (error as? OutboxFirstError)?.message ?? "Couldn't reach the hub — the change stays queued."
        }
    }
}

public enum OutboxFirstError: Error, Equatable, Sendable {
    /// No hub provider for this kind right now (no connection yet) — the row stays queued.
    case noProvider(String)
    /// The stored payload no longer decodes for its kind — left queued, never silently dropped.
    case undecodable(String)

    public var message: String {
        switch self {
        case .noProvider: "Not connected to the hub — the change stays queued."
        case .undecodable(let kind): "Queued \(kind) change could not be read — kept for inspection."
        }
    }
}

/// The process-wide kind → handler table every `OutboxDrainer` consults for kinds outside its own
/// built-in switch. MainActor: registration happens at launch, drains run on the main actor.
@MainActor
public final class OutboxFirstRegistry {
    public static let shared = OutboxFirstRegistry()
    private var handlers: [String: OutboxReplayHandler] = [:]
    public init() {}

    /// Registers (or replaces) the handler for `handler.kind`. Built-in drainer kinds are refused:
    /// two replay paths for one kind would double-send.
    public func register(_ handler: OutboxReplayHandler) {
        precondition(!OutboxDrainer.knownKinds.contains(handler.kind) && handler.kind != StrengthOutbox.kind,
                     "kind \(handler.kind) is already drained by OutboxDrainer's built-in switch")
        handlers[handler.kind] = handler
    }
    public func unregister(kind: String) { handlers[kind] = nil }
    public func handler(for kind: String) -> OutboxReplayHandler? { handlers[kind] }
    public var kinds: Set<String> { Set(handlers.keys) }
}

/// What `OutboxFirst.submit` did with a write.
public enum OutboxFirstOutcome: Equatable, Sendable {
    /// Queued and delivered in the same beat (hub reachable).
    case delivered
    /// Queued; the hub was not reached (or refused transiently). The drainer retries it on
    /// foreground / reachability regain / backoff. `reason` is the stored `lastError`.
    case queued(reason: String)
    /// The hub refused this row permanently (4xx other than 401) — retired, never retried.
    case rejected(reason: String)
    /// Could not even be written to the local queue (disk failure).
    case notQueued(reason: String)
}

/// B-52 p1 (a): the ONE way a screen performs a hub write — enqueue FIRST (durable before any
/// network call), then ask the drainer for an immediate pass, and report what happened to THIS row.
/// A write therefore never needs the hub up: offline it is `.queued`, and the drainer sends it later.
///
///     let outcome = await OutboxFirst(outbox: outbox, drainer: drainer)
///         .submit(kind: "training_break", payload: body)
@MainActor
public struct OutboxFirst {
    public let outbox: Outbox
    public let drainer: OutboxDrainer?
    public init(outbox: Outbox, drainer: OutboxDrainer?) { self.outbox = outbox; self.drainer = drainer }

    @discardableResult
    public func submit<P: Encodable>(kind: String, payload: P) async -> OutboxFirstOutcome {
        let id: Int64
        do { id = try outbox.enqueue(kind: kind, payload: payload) } catch {
            return .notQueued(reason: "Couldn't save the change on this phone: \(error.localizedDescription)")
        }
        guard let drainer else { return .queued(reason: OutboxFirstError.noProvider(kind).message) }
        var results = await drainer.drainOnce()
        // A pass already in flight when we enqueued did not see this row — one more pass for it.
        if results[id] == nil, (try? outbox.pending())?.contains(where: { $0.id == id }) == true {
            results = await drainer.drainOnce()
        }
        let row = (try? outbox.pending())?.first { $0.id == id }
        switch results[id] {
        case .success?: return .delivered
        case .failure(let error)?:
            if row == nil { return .rejected(reason: OutboxReplayHandler.defaultDescribe(error)) }
            return .queued(reason: row?.lastError ?? OutboxReplayHandler.defaultDescribe(error))
        case nil:
            // Coalesced into a newer row, or the pass did not reach it (in-flight pass started
            // before the enqueue): still pending → queued; gone → delivered with its group.
            return row == nil ? .delivered : .queued(reason: row?.lastError ?? "Queued — will sync when the hub is reachable.")
        }
    }
}
