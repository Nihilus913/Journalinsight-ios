import ActivityKit
import Foundation
import os

/// B-21 (push-to-start) — hands the verdict Live Activity's push-to-start token to the hub.
///
/// ActivityKit issues a per-device token on `Activity<VerdictActivityAttributes>.pushToStartTokenUpdates`
/// (iOS 17.2+). The hub's Morning GO sends an APNs `liveactivity` push with `event: "start"` to it,
/// which starts the verdict card on the Lock Screen at 05:10 even with the app killed;
/// `LiveActivityController.adoptRunning` then adopts that remotely-started activity on the next
/// launch/update (no second `Activity.request`).
///
/// Additive like the rest of APNs: no token (the Simulator never issues one, Live Activities off)
/// only means the 05:10 card is not pushed — the alert push, ntfy and the local floor are untouched.
/// Each token goes to `ApnsRegistration.receive(liveActivityStartToken:)`, which re-POSTs the device
/// registration and reuses its pending/retry path.
@MainActor
final class LiveActivityStartRegistration {
    static let shared = LiveActivityStartRegistration()

    private var task: Task<Void, Never>?
    private let logger = Logger(subsystem: "toby913.JournalInsight", category: "apns")

    init() {}

    /// True once `start` has spawned its observer — `start` is idempotent per instance.
    var isObserving: Bool { task != nil }

    /// Started once per cold launch from `JournalInsightApp`. `tokens`/`sink` are test seams; the
    /// defaults are the system stream and the shared `ApnsRegistration`.
    func start(
        tokens: @escaping @MainActor () -> AsyncStream<Data> = { LiveActivityStartRegistration.systemTokens() },
        sink: @escaping @MainActor (Data) async -> Void = { await ApnsRegistration.shared.receive(liveActivityStartToken: $0) }
    ) {
        guard task == nil else { return }
        logger.notice("Live Activity: push-to-start token unavailable until ActivityKit issues one (expected on the Simulator)")
        let stream = tokens()
        let logger = logger
        task = Task { @MainActor in
            for await data in stream {
                logger.notice("Live Activity: push-to-start token received (\(data.count, privacy: .public) bytes) — registering with the hub")
                await sink(data)
            }
        }
    }

    /// The system's push-to-start token stream, re-wrapped as an `AsyncStream` so `start` has one
    /// testable element type. Ends (and cancels the inner iteration) when the consumer goes away.
    nonisolated static func systemTokens() -> AsyncStream<Data> {
        AsyncStream { continuation in
            let inner = Task {
                for await data in Activity<VerdictActivityAttributes>.pushToStartTokenUpdates {
                    continuation.yield(data)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in inner.cancel() }
        }
    }
}
