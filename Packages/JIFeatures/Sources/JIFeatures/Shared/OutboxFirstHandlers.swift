import Foundation
import JICore
import JIPersistence

/// B-52 p4: the two hub writes that used to need the hub up, now outbox kinds replayed through
/// `OutboxFirstRegistry` (`OutboxFirst.submit` in the tap, every `OutboxDrainer` afterwards).
///
/// - `training_break` (`PUT /planning/training-break`): last-write-wins — however often the toggle
///   flips offline, only the NEWEST state is sent. `since` is stamped with the phone's day at the
///   tap, so a break turned on offline still starts the day it was turned on.
/// - `garmin_push` (`POST /workout-templates/{id}/push-garmin`): one row per template (repeat taps
///   coalesce). Idempotent on the hub: a template already linked to Garmin is PUT, not re-created.
///   503 (Garmin session expired on the mini) / 502 keep it queued; 404 / 422 retire it.
///
/// `import-garmin` is NOT a kind: it needs the hub by nature (card Q2) and stays disabled offline.
public enum B52WriteKinds {
    public nonisolated static let trainingBreak = "training_break"
    public nonisolated static let garminPush = "garmin_push"

    /// `PUT /planning/training-break`'s stored body.
    public static func trainingBreakHandler(
        provider: @escaping @MainActor @Sendable () -> (any TrainingBreakProviding)?
    ) -> OutboxReplayHandler {
        OutboxReplayHandler.make(
            kind: trainingBreak, payload: TrainingBreak.self,
            coalesce: { @Sendable _ in "break" },
            describe: { @Sendable error in "Break not synced yet — \(trainingBreakErrorText(error))" },
            send: { @MainActor (body: TrainingBreak) async throws in
                guard let hub = provider() else { throw OutboxFirstError.noProvider(trainingBreak) }
                _ = try await hub.setTrainingBreak(paused: body.paused, since: body.since)
            })
    }

    public static func garminPushHandler(
        provider: @escaping @MainActor @Sendable () -> (any WorkoutLibraryProviding)?
    ) -> OutboxReplayHandler {
        OutboxReplayHandler.make(
            kind: garminPush, payload: GarminPushWrite.self,
            coalesce: { @Sendable body in String(body.templateId) },
            describe: { @Sendable error in WorkoutLibraryViewModel.describeGarmin(error) },
            send: { @MainActor (body: GarminPushWrite) async throws in
                guard let hub = provider() else { throw OutboxFirstError.noProvider(garminPush) }
                _ = try await hub.pushWorkoutTemplateToGarmin(id: body.templateId)
            })
    }

    /// Launch wiring: every process-wide drainer (watchdog regain, retry scheduler, BG refresh)
    /// can deliver both kinds over whatever hub is current when the row is replayed.
    @MainActor
    public static func registerAll(in registry: OutboxFirstRegistry = .shared,
                                   hub: @escaping @MainActor @Sendable () -> (any Sendable)?) {
        registry.register(trainingBreakHandler(provider: { hub() as? any TrainingBreakProviding }))
        registry.register(garminPushHandler(provider: { hub() as? any WorkoutLibraryProviding }))
    }

    /// A drainer for ONE screen's own in-tap attempt: only `handler`'s kind, over that screen's
    /// provider (so a preview / fixture never reaches the process-wide registry). Rows it leaves
    /// queued are delivered later by the launch-registered drainers.
    @MainActor
    static func localDrainer(outbox: Outbox, handler: OutboxReplayHandler) -> OutboxDrainer {
        let registry = OutboxFirstRegistry()
        registry.register(handler)
        return OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, registry: registry)
    }

    /// The newest queued payload of `kind` (decoded), or nil.
    @MainActor
    static func newestPending<P: Decodable>(_ kind: String, in outbox: Outbox?, as: P.Type) -> P? {
        guard let row = ((try? outbox?.pending()) ?? []).last(where: { $0.kind == kind }) else { return nil }
        return try? JSONDecoder().decode(P.self, from: row.payload)
    }

    /// Every queued payload of `kind` (decodable ones), oldest first.
    @MainActor
    static func allPending<P: Decodable>(_ kind: String, in outbox: Outbox?, as: P.Type) -> [P] {
        ((try? outbox?.pending()) ?? []).filter { $0.kind == kind }
            .compactMap { try? JSONDecoder().decode(P.self, from: $0.payload) }
    }

    /// "yyyy-MM-dd" in the phone's calendar.
    nonisolated static func localDay(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }
}

/// `garmin_push`'s stored body.
public nonisolated struct GarminPushWrite: Codable, Sendable, Equatable {
    public var templateId: Int
    public init(templateId: Int) { self.templateId = templateId }
}
