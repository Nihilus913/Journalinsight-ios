import Testing
import JIPersistence
@testable import JIFeatures

struct TodayPageNameTests {
    @Test func blankOrWhitespaceFallsBackToToday() {
        #expect(normalizedTodayPageName("   ") == "Today")
        #expect(normalizedTodayPageName("") == "Today")
        #expect(normalizedTodayPageName("  Morning  ") == "Morning")
        #expect(normalizedTodayPageName(String(repeating: "x", count: 40)).count == 24)
    }

    @Test func roundTripsThroughPrefStore() throws {
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        #expect(loadTodayPageName(prefs: prefs) == "Today")
        saveTodayPageName("Plan", prefs: prefs)
        #expect(loadTodayPageName(prefs: prefs) == "Plan")
        #expect(loadTodayPageName(prefs: nil) == "Today")
    }
}
