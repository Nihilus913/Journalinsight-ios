import Foundation
import Testing
import JICore
@testable import JIFeatures

/// W-B57-W2 L2 guard (BUG-07, XC side): the 7-day energy balance is intake − expenditure, the
/// negation of the hub's single definition `avg_kcal_deficit_7d` (= expenditure − intake). Never
/// the gap to a kcal goal, never a bare 0 when the hub has no deficit. W2's EnergyBand balance
/// (intake − burn, negative = deficit) must keep this sign.
@Suite struct B57W2L2BalanceGuardTests {
    private func averages(_ json: String) throws -> GateAverages {
        try JSON.decoder.decode(GateAverages.self, from: Data(json.utf8))
    }

    @Test func deficitWireKeyBecomesANegativeBalance() throws {
        let a = try averages(#"{"avg_kcal_deficit_7d": 500, "avg_kcal_7d": 1800, "trends": {}}"#)
        #expect(a.avgKcalDeficit7d == 500)
        #expect(weeklyEnergyBalance(a) == -500)
    }

    @Test func surplusIsAPositiveBalance() throws {
        let a = try averages(#"{"avg_kcal_deficit_7d": -220.5, "trends": {}}"#)
        #expect(weeklyEnergyBalance(a) == 220.5)
    }

    /// The balance is never the gap to a goal: avg intake alone (no deficit) gives nil, not a number.
    @Test func noHubDeficitIsNilNeverZero() throws {
        let a = try averages(#"{"avg_kcal_7d": 1617, "trends": {}}"#)
        #expect(weeklyEnergyBalance(a) == nil)
    }
}
