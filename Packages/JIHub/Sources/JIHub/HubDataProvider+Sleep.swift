import Foundation
import JICore

/// W-FIX2 L5 (FM-08 app side): the app finally calls `/vitals/sleep-summary`.
extension HubDataProvider: SleepSummaryProviding {
    public func sleepSummary() async throws -> SleepSummary {
        try await client.get("/api/v1/vitals/sleep-summary")
    }
}
