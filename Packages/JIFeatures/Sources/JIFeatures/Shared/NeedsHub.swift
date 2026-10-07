import Foundation
import JICore

/// W-OFFLINE OFF-1 (B-50 slice 1): whether a hub-only screen's model has a hub behind it.
/// `.needsHub` = no hub configured, or the active data source speaks none of the screen's
/// `<Screen>Providing` protocols (the on-device `HealthKitProvider`). Such a model shows what the
/// OfflineCache holds, else one honest "Connect the hub" line — never a blank tab, an endless
/// spinner, or a hub call it cannot make.
public enum HubAvailability: Equatable, Sendable {
    case live
    case needsHub

    /// W-OFFLINE2 OFF2-3: whether the screen's error card offers Retry. A `.needsHub` card has
    /// nothing to retry (a refresh only re-settles the same line), so it shows none.
    nonisolated public var offersRetry: Bool { if case .live = self { true } else { false } }
}

/// The one honest line a hub-only screen shows when there is no hub and nothing cached.
public nonisolated enum NeedsHubCopy {
    public static func line(_ what: String) -> String { "Connect the hub in Settings to see \(what)." }
    public static let energy = line("your energy balance")
    public static let nutrition = line("your nutrition")
    public static let training = line("your training plan")
    public static let goals = line("your goals")
}

/// The error a `NeedsHubProvider` throws; a `.needsHub` model never calls it on its load path.
public struct NeedsHubError: Error, Equatable, Sendable {
    public init() {}
}

/// Stands in for the hub when there is none, so a hub-only screen still gets a model (in
/// `.needsHub`). Every read throws `NeedsHubError`; nothing here reaches a network.
public struct NeedsHubProvider: HealthDataProvider, EnergyProviding, NutritionProviding, TrainingProviding {
    public init() {}

    public var capabilities: DataCapability { [] }
    public func health() async throws -> HealthResponse { throw NeedsHubError() }
    public func gate(windowDays: Int) async throws -> GateResponse { throw NeedsHubError() }
    public func morning() async throws -> MorningResponse { throw NeedsHubError() }
    public func morningVerdict(date: String) async throws -> MorningVerdict { throw NeedsHubError() }
    public func recovery(windowDays: Int) async throws -> [RecoveryDay] { throw NeedsHubError() }
    public func syncStatus() async throws -> SyncStatus { throw NeedsHubError() }

    public func energy(windowDays: Int) async throws -> EnergyReport { throw NeedsHubError() }
    public func goals() async throws -> Goals { throw NeedsHubError() }

    public func nutritionDay(date: String) async throws -> NutritionDayDetail? { throw NeedsHubError() }
    public func nutritionWeek(windowDays: Int) async throws -> [NutritionDailyRow] { throw NeedsHubError() }

    public func trainingDay(date: String) async throws -> TrainingDayDetail { throw NeedsHubError() }
    public func exercises() async throws -> [Exercise] { throw NeedsHubError() }
    public func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult { throw NeedsHubError() }
}
