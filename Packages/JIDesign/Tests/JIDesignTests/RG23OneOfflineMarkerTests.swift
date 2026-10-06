import Foundation
import Testing
@testable import JIDesign

/// W-FIX-P2 RG-23 (B-52): offline shows ONE marker. The screen's amber "Offline · last hh:mm"
/// pill is it — the sync pill ("Synced hh:mm" / "Not synced yet") steps aside while offline.
@Suite struct RG23OneOfflineMarkerTests {
    @Test func syncPillIsHiddenWhileOffline() {
        #expect(syncedPillVisible(offline: true) == false)
        #expect(syncedPillVisible(offline: false) == true)
    }

    @Test func offlineFaceIsTheOfflinePillOnly() {
        // the one offline face names the sync time once
        #expect(offlinePillText(lastTime: "07:04") == "Offline · last 07:04")
        #expect(offlinePillVisible(fetchedAt: nil, hubReachable: false, now: Date()))
    }
}
