import Testing
@testable import JournalInsight

struct MoreTabTests {
    @Test func moreIsTrackPracticeAppWithNoChallenges() {
        let s = RootTabView.moreSections
        #expect(s.map(\.header) == ["Track", "Practice", "App"])
        #expect(s.flatMap(\.rows) == ["Nutrition", "Energy", "My KPIs", "Goals", "Mind", "Settings"])
        #expect(!s.flatMap(\.rows).contains("Challenges"))
    }

    @Test func myKpisRowShowsTheChosenCount() {
        #expect(RootTabView.moreKpiText(count: 5) == "5 chosen")
    }
}
