import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// Posts the on-device verdict as a LOCAL notification (the App's `UNUserNotificationCenter`
/// adapter; a recorder in tests).
public protocol OnDeviceVerdictNotifying: Sendable {
    func postVerdict(day: String, result: OnDeviceVerdictResult) async
}

/// Which verdict was last notified per day. Persisted by the App (a background wake may be a
/// fresh process), in memory in tests.
public protocol OnDeviceVerdictMemory: Sendable {
    func lastNotified(day: String) -> String?
    func setLastNotified(_ verdict: String, day: String)
}

public final class InMemoryVerdictMemory: OnDeviceVerdictMemory, @unchecked Sendable {
    // `@unchecked`: the dictionary is only touched under `lock`.
    private let lock = NSLock()
    private var values: [String: String] = [:]
    public init() {}
    public func lastNotified(day: String) -> String? { lock.withLock { values[day] } }
    public func setLastNotified(_ verdict: String, day: String) { lock.withLock { values[day] = verdict } }
}

/// W-ONDEVICE O-9: the idempotent trigger entry point `run(day)`.
///
/// HealthKit delivers a night in several batches (sleep stages, then HRV), so the observer fires
/// several times per morning. Every call recomputes (cheap, pure), but a local notification goes
/// out only on the **first complete night** (the compute returns a result) or when the verdict
/// **changes**. Calls are serialised (a chain of tasks), so three concurrent observer wakes can
/// never all see "not notified yet".
///
/// A locked phone: HealthKit's protected store throws `errorDatabaseInaccessible` before first
/// unlock. The day is remembered (`pendingDay`) and recomputed on `protectedDataBecameAvailable()`;
/// meanwhile the 05:10 `LocalVerdictFloor` (always scheduled) is the fallback the user sees.
public actor OnDeviceVerdictRunner {
    public enum Outcome: Sendable, Equatable {
        case notified
        case unchanged
        /// No complete night for the day yet.
        case missing
        /// HealthKit was locked; retried on unlock.
        case deferredLocked
        case failed(String)
    }

    public typealias Compute = @Sendable (String) async throws -> OnDeviceVerdictResult?
    /// Every computed result (notified or not), with its compute time — the O-10 shadow log hook.
    public typealias ResultObserver = @Sendable (String, OnDeviceVerdictResult, Date) async -> Void

    private let compute: Compute
    private let notifier: any OnDeviceVerdictNotifying
    private let memory: any OnDeviceVerdictMemory
    private let onResult: ResultObserver?
    private let now: @Sendable () -> Date
    private var tail: Task<Outcome, Never>?
    public private(set) var pendingDay: String?

    public init(
        compute: @escaping Compute,
        notifier: any OnDeviceVerdictNotifying,
        memory: any OnDeviceVerdictMemory = InMemoryVerdictMemory(),
        onResult: ResultObserver? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.compute = compute; self.notifier = notifier; self.memory = memory
        self.onResult = onResult; self.now = now
    }

    /// Recompute `day`; notify only on the first complete night or a changed verdict.
    @discardableResult
    public func run(day: String) async -> Outcome {
        let previous = tail
        let task = Task { [weak self] () -> Outcome in
            _ = await previous?.value
            guard let self else { return .failed("runner released") }
            return await self.runNow(day: day)
        }
        tail = task
        return await task.value
    }

    /// The phone was unlocked: rerun a day that hit the protected-data error. `nil` = nothing pending.
    @discardableResult
    public func protectedDataBecameAvailable() async -> Outcome? {
        guard let day = pendingDay else { return nil }
        return await run(day: day)
    }

    private func runNow(day: String) async -> Outcome {
        let result: OnDeviceVerdictResult?
        do {
            result = try await compute(day)
        } catch {
            if Self.isProtectedDataError(error) {
                pendingDay = day
                return .deferredLocked
            }
            return .failed(String(describing: error))
        }
        if pendingDay == day { pendingDay = nil }
        guard let result else { return .missing }
        await onResult?(day, result, now())
        if memory.lastNotified(day: day) == result.verdict { return .unchanged }
        memory.setLastNotified(result.verdict, day: day)
        await notifier.postVerdict(day: day, result: result)
        return .notified
    }

    /// HealthKit's "protected data unavailable" (device locked since boot / screen locked).
    public static func isProtectedDataError(_ error: any Error) -> Bool {
        #if canImport(HealthKit)
        if let hk = error as? HKError { return hk.code == .errorDatabaseInaccessible }
        let ns = error as NSError
        return ns.domain == HKErrorDomain && ns.code == HKError.Code.errorDatabaseInaccessible.rawValue
        #else
        return false
        #endif
    }
}

/// W-ONDEVICE O-9: the BGAppRefresh pre-warm (baselines + last inputs) is asked for ~04:45 local,
/// so the observer-driven compute after wake finds a warm store. iOS picks the real minute;
/// correctness never depends on it (the observer + the 05:10 floor do).
public enum OnDevicePrewarm {
    public static let taskIdentifier = "toby913.JournalInsight.verdictPrewarm"
    public static let hour = 4
    public static let minute = 45

    /// The next 04:45 strictly after `date` in `calendar`'s zone.
    public static func nextBegin(after date: Date, calendar: Calendar) -> Date? {
        calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute, second: 0), matchingPolicy: .nextTime)
    }
}
