import Testing
@testable import JIDesign

// B-57 W1 §0.2: missing data is "—" + one of three reason words, never a zero.
struct SignalStatusTests {
    @Test func missingReasonsAreTheThreeSpecWords() {
        #expect(JIMissingReason.allCases.map(\.rawValue) == ["Calibrating", "No data", "Not in Health yet"])
    }

    @Test func everyStatusHasAWordARoleAndASymbol() {
        let all: [JISignalStatus] = [.aboveGoal, .belowGoal, .onGoal, .inNormal, .belowNormal, .aboveNormal,
                                     .clear, .watch, .redFlag, .contextOnly, .missing(.noData)]
        for s in all {
            #expect(!s.word.isEmpty)
            #expect(!s.symbolName.isEmpty)
        }
        #expect(JISignalStatus.missing(.calibrating).word == "Calibrating")
        #expect(JISignalStatus.inNormal.word == "In your normal")
        #expect(JISignalStatus.belowNormal.word == "Below your normal")
        #expect(JISignalStatus.watch.word == "Watch")
    }

    @Test func tintIsWordedNeverColourAlone() {
        #expect(JISignalStatus.clear.role == .go)
        #expect(JISignalStatus.watch.role == .reduced)
        #expect(JISignalStatus.redFlag.role == .danger)
        #expect(JISignalStatus.contextOnly.role == .muted)
        #expect(JISignalStatus.missing(.noData).role == .muted)
        #expect(JISignalStatus.contextOnly.role != .go)    // rule 6
    }

    @Test func numbersAreLocaleFreeAndNilIsAnEmDash() {
        #expect(jiNumber(27.46, 1) == "27.5")
        #expect(jiNumber(1617, 0) == "1617")
        #expect(jiValueText(nil, decimals: 0) == "—")
        #expect(jiValueText(0.0, decimals: 2) == "0.00")    // a REAL zero still prints; only nil is "—"
        #expect(jiValueOrReasonText(nil, decimals: 0, unit: "g") == "— No data")
        #expect(jiValueOrReasonText(nil, decimals: 0, reason: .notInHealthYet) == "— Not in Health yet")
        #expect(jiValueOrReasonText(12.4, decimals: 0, unit: "g") == "12 g")
        #expect(jiValueOrReasonText(1617, decimals: 0) == "1617")
    }
}
