import SwiftUI
import JIDesign

/// Every native component at once, fixture-backed. Test-only: rendered by the sweep, never
/// routed to from the app. Update it when a JIDesign component is added.
public struct NativeGalleryView: View {
    @State private var range: TrendRange = .week
    @State private var selectedDay: Date? = nil
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.locale = Locale(identifier: "en_US"); return c }
    private let today = Date(timeIntervalSince1970: 1_789_992_000) // 2026-09-21 12:00 UTC
    private var trend: [TrendPoint] {
        (0..<7).map { TrendPoint(date: today.addingTimeInterval(Double($0 - 6) * 86_400), value: [48, 50, 47, 53, 51, 49, 52][$0]) }
    }

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                JISectionHeader("Readiness")
                AdaptiveHStack {
                    Surface { ReadinessArcGauge(score: 72).frame(maxWidth: .infinity) }
                    Surface {
                        HStack(spacing: 24) {
                            VStack { ScoreRing(value: 85, max: 100, tint: .purple); Text("Sleep").jiFont(.caption) }
                            VStack { ScoreRing(value: 6_400, max: 8_000, tint: .orange); Text("Steps").jiFont(.caption) }
                            VStack { MacroRings(protein: .init(value: 120, goal: 160), carbs: .init(value: 210, goal: 250), fat: .init(value: 55, goal: 70)); Text("Macros").jiFont(.caption) }
                        }.frame(maxWidth: .infinity)
                    }
                }
                JISectionHeader("Summary")
                Columns(minimum: 160) {
                    SummaryCard(icon: "waveform.path.ecg", tint: .red, title: "HRV", value: "52", unit: "ms", timestamp: "Today, 07:12", sparkline: [48, 50, 47, 53, 51, 49, 52], action: {})
                    SummaryCard(icon: "heart.fill", tint: .red, title: "Resting HR", value: "54", unit: "bpm", timestamp: "Today, 07:12", sparkline: [56, 55, 57, 54, 55, 53, 54], action: {})
                    SummaryCard(icon: "bed.double.fill", tint: .purple, title: "Sleep", value: "7h 40m", timestamp: "Last night", action: {})
                    SummaryCard(icon: "battery.75percent", tint: .teal, title: "Body Battery", value: nil, sourceMissing: true)
                }
                JISectionHeader("Trend")
                Surface { TrendChart(points: trend, tint: .red, unit: "ms", range: $range, showAll: {}) }
                JISectionHeader("Week")
                Surface { WeekStrip(days: weekStripDays(ending: today, marked: [today], calendar: calendar), tint: .green, selected: $selectedDay) }
                JISectionHeader("Rows")
                Surface(padding: 0) {
                    VStack(spacing: 0) {
                        JIRow(title: "Sleep score", subtitle: "Last night", systemImage: "bed.double.fill", tint: .purple) { Text("85") }.padding(.horizontal, 16)
                        Divider().padding(.leading, 56)
                        JIRow(title: "Steps", systemImage: "figure.walk", tint: .orange) { Text("6,400") }.padding(.horizontal, 16)
                    }
                }
            }
            .padding(16)
            .readableColumn()
        }
        .modifier(GalleryBackground())
    }
}

private struct GalleryBackground: ViewModifier {
    @Environment(\.jiTheme) private var theme
    func body(content: Content) -> some View { content.background(theme.color(.bg)) }
}
