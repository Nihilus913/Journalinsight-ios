import Foundation
import Observation
import JICore

/// Drives the HealthKit backload (W2h, B-9) from Settings. Built against the frozen
/// `BackloadRunning` protocol only — JIFeatures never imports JIHealthKit (see the wave card);
/// `AppEnvironment` injects the real `HealthKitBackloader`, tests inject a fake runner.
@Observable @MainActor
public final class HealthBackloadViewModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case authorizing
        case running(monthIndex: Int, monthCount: Int, written: Int, skipped: Int)
        case done(BackloadSummary)
        case failed(String)
    }

    public private(set) var phase: Phase = .idle

    private let runner: any BackloadRunning
    private let now: () -> Date

    /// Default range: hub has Garmin (dso_key = 2) since 2025-05-27 (wave card §Why/what) through today.
    public init(runner: any BackloadRunning, now: @escaping () -> Date = Date.init) {
        self.runner = runner
        self.now = now
    }

    public var defaultRange: BackloadRange {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
        let from = cal.date(from: DateComponents(year: 2025, month: 5, day: 27)) ?? now()
        return BackloadRange(from: from, to: now())
    }

    public var isRunning: Bool {
        switch phase {
        case .authorizing, .running: true
        default: false
        }
    }

    public func start() async {
        phase = .authorizing
        do {
            try await runner.authorize()
        } catch let error as BackloadError {
            phase = .failed(Self.describe(error))
            return
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        await run(defaultRange)
    }

    private func run(_ range: BackloadRange) async {
        do {
            let summary = try await runner.run(range) { [weak self] progress in
                // `BackloadRunning.run` calls this synchronously on its own caller's task (see
                // JICore's contract doc); every conforming runner (fake or real) invokes it from
                // the same MainActor task that awaited `run`, so this is safe despite the
                // `@Sendable` signature required by the frozen protocol.
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.phase = .running(
                        monthIndex: progress.monthIndex,
                        monthCount: progress.monthCount,
                        written: progress.written,
                        skipped: progress.skipped
                    )
                }
            }
            phase = .done(summary)
        } catch let error as BackloadError {
            phase = .failed(Self.describe(error))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private static func describe(_ error: BackloadError) -> String {
        switch error {
        case .healthDataUnavailable: "Health data isn't available on this device."
        case .authorizationDenied: "Health access was denied. Enable it in Settings > Health > Data Access."
        case .hub(let message): "Hub error: \(message)"
        }
    }
}
