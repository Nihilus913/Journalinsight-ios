import Foundation
import Testing
import JIDesign
@testable import JIFeatures

// W-FIX-P3 RG-87: SF Symbols carry the app's words for VoiceOver, never Apple's symbol names
// ("Love", "Do Not Disturb", "brightness higher", "Ecg Waveform Path"); the hub's amber status
// word is "Caution" — "Watch" is the device the Recovery data comes from.

private let appleSymbolNames: Set<String> = ["Love", "love", "Do Not Disturb", "brightness higher", "Ecg Waveform Path",
                                             "Dumbbell weight, filled", "Dumbbell weight", "Forward"]

@Suite struct FixP3SymbolLabelTests {
    @Test func recoveryCardIconsHaveAppLabels() {
        for m in RecoveryCardMetric.allCases {
            let label = jiSymbolAccessibilityLabel(m.symbol, title: m.title)
            #expect(label == m.title)
            #expect(!appleSymbolNames.contains(label))
            #expect(label != m.symbol)
        }
    }

    @Test func tabBarSymbolsHaveAppLabels() {
        // RootTab (App target) symbols → its titles.
        let tabs = [("sun.max", "Today"), ("book.closed", "Journal"), ("heart", "Recovery"), ("flame", "Energy"),
                    ("fork.knife", "Nutrition"), ("dumbbell", "Training"), ("magnifyingglass", "Search"), ("ellipsis", "More")]
        for (symbol, title) in tabs {
            #expect(jiSymbolAccessibilityLabel(symbol, title: title) == title)
        }
    }

    @Test func amberStatusIsNotWatch() {
        #expect(JISignalStatus.watch.word == "Caution")
        #expect(decideSignalWordIsNotDevice(JISignalStatus.watch.word))
    }
}

private func decideSignalWordIsNotDevice(_ w: String) -> Bool { !w.localizedCaseInsensitiveContains("watch") }
