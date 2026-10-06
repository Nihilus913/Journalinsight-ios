import Foundation
import Testing
import JIPersistence
import JIWorkouts
@testable import JIFeatures

// RG-76 (B-43): the requestAuthorization() Bool was discarded at TrainingView / PlannerStrengthDetail;
// a denial is now the phone logger's visible 'Notifications off' state.
@MainActor @Suite struct RestAlertDeniedStateTests {
    func model() throws -> JIFeatures.StrengthLogViewModel {
        JIFeatures.StrengthLogViewModel(lifts: [], sessionId: nil, sessionName: nil, store: StrengthSessionLogStore(db: try AppDatabase.inMemory()),
                             outbox: nil, provider: nil, prefs: nil, today: { "2026-10-06" })
    }

    @Test func deniedShowsNotificationsOff() async throws {
        let m = try model()
        #expect(!m.restAlertsOff)
        await m.requestRestAlertPermission { false }
        #expect(m.restAlertsOff)
        #expect(RestEndAlert.offNotice.contains("Notifications off"))
    }

    @Test func grantedKeepsAlertsOn() async throws {
        let m = try model()
        await m.requestRestAlertPermission { true }
        #expect(!m.restAlertsOff)
    }
}
