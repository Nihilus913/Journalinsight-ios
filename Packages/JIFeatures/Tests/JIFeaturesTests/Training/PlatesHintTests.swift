import Foundation
import Testing
@testable import JIFeatures

/// W-FIX-P3 RG-67: the "plates" line under the set entry is hidden for bodyweight lifts and for a
/// prescribed dumbbell weight the plates cannot build (12 kg per hand = a fixed dumbbell).
@Suite struct PlatesHintTests {
    static func lift(_ key: String, kg: Double?) -> StrengthLogLift {
        StrengthLogLift(exerciseId: 1, exerciseKey: key, sets: 3, repsTarget: "8", currentKg: kg, stepKg: 2.5, nextKg: nil)
    }

    @Test func bodyweightLiftHasNoHint() {
        #expect(Self.lift("Pull-up", kg: 0).isBodyweight)
        #expect(Self.lift("Push-up", kg: nil).isBodyweight)
        #expect(StrengthFormat.platesHint(nil, load: .barbell, bodyweight: true) == nil)
        #expect(StrengthFormat.platesHint([10], load: .barbell, bodyweight: true) == nil)
    }

    @Test func prescribedDumbbellTheInventoryCannotBuildHasNoHint() {
        // 12 kg per hand: not plate-loadable -> hidden, never "Not reachable with your plates"
        #expect(StrengthFormat.platesHint(nil, load: .dumbbell, bodyweight: false) == nil)
    }

    @Test func kettlebellIsAFixedWeight() {
        #expect(StrengthLoad.isFixedWeight("KB Swing"))
        #expect(StrengthLoad.isFixedWeight("Kettlebell Goblet Squat"))
        #expect(!StrengthLoad.isFixedWeight("Bench Press"))
        #expect(!StrengthLoad.isFixedWeight("DB Row"))
    }

    @Test func barbellKeepsItsHints() {
        #expect(!Self.lift("Bench Press", kg: 50).isBodyweight)
        #expect(StrengthFormat.platesHint([15], load: .barbell, bodyweight: false) == "Per side: 15")
        #expect(StrengthFormat.platesHint(nil, load: .barbell, bodyweight: false) == "Not reachable with your plates")
        #expect(StrengthFormat.platesHint([], load: .dumbbell, bodyweight: false) == "Empty handle")
    }
}
