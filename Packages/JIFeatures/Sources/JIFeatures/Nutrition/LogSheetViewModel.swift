import Foundation
import Observation
import JICore

/// PINNED FOOD-LOG CONTRACT (`useLogFoodActions.ts`) — the log/delete sheet's own tiny state
/// machine. 409/502 map to the named `HubError` cases and show the oracle's copy verbatim
/// (`describeLogFoodError` in `useLogFoodActions.ts` L70-95).
@Observable @MainActor
public final class LogSheetViewModel {
    public enum SubmitState: Equatable, Sendable {
        case idle
        case submitting
        case success(LogFoodResult)
        case failure(String)
    }

    public private(set) var state: SubmitState = .idle
    private let provider: any NutritionProviding

    public init(provider: any NutritionProviding) { self.provider = provider }

    @discardableResult
    public func submitTemplate(_ templateId: String, meal: MealSlot) async -> LogFoodResult? {
        await submit(LogFoodBody(meal: meal, template: templateId))
    }

    @discardableResult
    public func submitItems(_ items: [LogFoodItemInput], meal: MealSlot) async -> LogFoodResult? {
        await submit(LogFoodBody(meal: meal, items: items))
    }

    private func submit(_ body: LogFoodBody) async -> LogFoodResult? {
        state = .submitting
        do {
            let result = try await provider.logFood(body)
            state = .success(result)
            return result
        } catch {
            state = .failure(Self.describe(error))
            return nil
        }
    }

    @discardableResult
    public func delete(itemId: String, date: String? = nil) async -> Bool {
        do {
            try await provider.deleteLogItem(itemId: itemId, date: date)
            return true
        } catch {
            state = .failure(Self.describe(error))
            return false
        }
    }

    /// Verbatim RN copy — `describeLogFoodError` in `mobile/src/data/useLogFoodActions.ts`.
    public static func describe(_ error: Error) -> String {
        switch error as? HubError {
        case .duplicate: "Already logged today."
        case .yazioAuthExpired: "YAZIO login expired — reconnect on the Mac."
        case .network: "Couldn't reach the hub — check your connection and try again."
        case .unauthorized: "Hub rejected the token — check Settings › Connection."
        case .http(_, let detail):
            if let detail, !detail.isEmpty { detail } else { "Couldn't log — try again." }
        case .decoding, .none: "Couldn't log — try again."
        }
    }
}
