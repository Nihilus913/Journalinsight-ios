import SwiftUI
import JIDesign

/// Every native component at once, fixture-backed. Test-only: rendered by the sweep, never
/// routed to from the app. Update it when a JIDesign component is added.
/// W-GUI F10: the gallery's segments — each forces one rendering condition on the contact
/// sheet (scheme, AX3, or a material fallback through `jiAccessibilityOverrides`).
public nonisolated enum GallerySegment: String, CaseIterable, Sendable, Identifiable {
    case dark = "Dark", light = "Light", ax3 = "AX3", reduceTransparency = "Reduce Transparency", increaseContrast = "Increase Contrast"
    public var id: String { rawValue }
    public var colorScheme: ColorScheme? { self == .light ? .light : (self == .dark ? .dark : nil) }
    public var typeSize: DynamicTypeSize? { self == .ax3 ? .accessibility3 : nil }
    public var reduceTransparency: Bool? { self == .reduceTransparency ? true : nil }
    public var increaseContrast: Bool? { self == .increaseContrast ? true : nil }
}

public struct NativeGalleryView: View {
    @State private var segment: GallerySegment? = nil
    @State private var range: TrendRange = .week
    @State private var selectedDay: Date? = nil
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.locale = Locale(identifier: "en_US"); return c }
    private let today = Date(timeIntervalSince1970: 1_789_992_000) // 2026-09-21 12:00 UTC
    private var trend: [TrendPoint] {
        (0..<7).map { TrendPoint(date: today.addingTimeInterval(Double($0 - 6) * 86_400), value: [48, 50, 47, 53, 51, 49, 52][$0]) }
    }

    public init() {}

    public var body: some View {
        // Test-only contact sheet: a plain stack, not a `ScrollView` — `ImageRenderer` renders a
        // `ScrollView`'s background but never its content off-screen, so the sweep would be blank.
        VStack {
            // W-GUI F10: the segments (the sweep leaves them unset and drives the cell itself).
            Picker("Condition", selection: $segment) {
                Text("Cell").tag(GallerySegment?.none)
                ForEach(GallerySegment.allCases) { Text($0.rawValue).tag(GallerySegment?.some($0)) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("gallery.segment")
            // W-GUI F10: `ScreenScroll` — a real ScrollView in the app (the gallery is taller than
            // any phone), the top-pinned stack under `jiOffscreenRender` so the sweep shows the top.
            ScreenScroll { sheet }
                .environment(\.dynamicTypeSize, segment?.typeSize ?? .large)
                .jiAccessibilityOverrides(reduceTransparency: segment?.reduceTransparency, increaseContrast: segment?.increaseContrast)
                .modifier(OptionalColorScheme(scheme: segment?.colorScheme))
        }
        .jiPageGround()
        .jiTheme(.native)
    }

    private var sheet: some View {
        VStack {
            VStack(alignment: .leading, spacing: 24) {
                // W-GUI F10: the F-step primitives — tinted hero, tile families, chevron rows, pill, buttons.
                JISectionHeader("Depth")
                Surface(tint: JIAccent.shared.color) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR CALL FOR TODAY").jiFont(.caption, weight: .bold).foregroundStyle(.secondary)
                        Text("Go").jiNumeral(.numeralHero, tint: .go)
                        HStack(spacing: 12) {
                            Button("Go with this") {}.buttonStyle(.jiPrimary)
                            Button("Adjust") {}.buttonStyle(.jiSecondary)
                        }
                    }
                }
                HStack(spacing: JISpacing.tileGap) {
                    JITile(family: .macroTile) { VStack(alignment: .leading) { Text("Protein").jiFont(.caption); Text("98 g").jiNumeral(.numeralCompact, tint: .protein) } }
                    JITile(family: .macroTile) { VStack(alignment: .leading) { Text("Carbs").jiFont(.caption); Text("111 g").jiNumeral(.numeralCompact, tint: .carbs) } }
                    JITile(family: .macroTile) { VStack(alignment: .leading) { Text("Fat").jiFont(.caption); Text("38 g").jiNumeral(.numeralCompact, tint: .fat) } }
                }
                HStack(spacing: JISpacing.tileGap) {
                    JITile(family: .factTile) { Text("Resp — not read").jiFont(.caption) }
                    JITile(family: .factTile) { Text("Wrist temp — not read").jiFont(.caption) }
                    JIAddTile(family: .factTile, label: "Add") {}
                }
                HStack { SyncedPill(date: today, now: today, calendar: calendar); SyncedPill(date: today.addingTimeInterval(-90_000), now: today, calendar: calendar); SyncedPill(date: nil) }
                Surface(padding: 0) {
                    VStack(spacing: 0) {
                        JIChevronRow(title: "Settings", value: "Hub synced 07:41", systemImage: "slider.horizontal.3").padding(.horizontal, 16)
                        Divider().padding(.leading, 60)
                        JIChevronRow(title: "How the morning call works", systemImage: "questionmark.circle").padding(.horizontal, 16)
                    }
                }
                JISectionHeader("Readiness")
                AdaptiveHStack {
                    Surface { ReadinessArcGauge(score: 72).frame(maxWidth: .infinity) }
                    Surface {
                        // A ring row is fixed-width art: at AX sizes it stops fitting side by side,
                        // so it reflows into a grid instead of pushing the whole sheet wider (§8.1).
                        Columns(minimum: 100, spacing: 24) {
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
                // W-GUI F5: the 44 pt glass round buttons (the only glass beside the coach overlay).
                JISectionHeader("Glass buttons")
                GlassEffectContainer {
                    HStack(spacing: 12) {
                        JIGlassButton("chevron.left", label: "Back") {}
                        JIGlassButton("pencil", label: "Edit") {}
                        JIGlassButton("calendar", label: "Calendar") {}
                        JIGlassButton("plus", label: "Add") {}
                    }
                }
                JISectionHeader("Rows")
                Surface(padding: 0) {
                    VStack(spacing: 0) {
                        JIRow(title: "Sleep score", subtitle: "Last night", systemImage: "bed.double.fill", tint: .purple) { Text("85") }.padding(.horizontal, 16)
                        Divider().padding(.leading, 56)
                        JIRow(title: "Steps", systemImage: "figure.walk", tint: .orange) { Text("6,400") }.padding(.horizontal, 16)
                    }
                }
                JISectionHeader("Against your normal")
                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        NormalBarLegend()
                        NormalBar(value: 127, normal: 120...150, median: 135, goal: 155, unit: "g", tint: .info)
                        NormalBar(value: 25, normal: nil, unit: "ms", tint: .info)
                    }
                }
                Surface {
                    NormalBarChart(points: [
                        NormalBarPoint(id: "1", label: "Thu", value: 29, isLatest: false),
                        NormalBarPoint(id: "2", label: "Fri", value: 28, isLatest: false),
                        NormalBarPoint(id: "3", label: "Sat", value: nil, isLatest: false),
                        NormalBarPoint(id: "4", label: "Wed", value: 25, isLatest: true),
                    ], normal: 27...30, unit: "ms")
                }
                JISectionHeader("Squares")
                SquareGrid(items: [
                    JISquareItem(id: "hrv", label: "HRV", systemImage: "waveform.path.ecg", tint: .info, value: 25, unit: "ms", status: .watch, badge: .hide),
                    JISquareItem(id: "rhr", label: "Resting HR", systemImage: "heart", tint: .danger, value: nil, status: .missing(.noData), badge: .hide),
                    JISquareItem(id: "load", label: "Load", systemImage: "bolt", tint: .reduced, value: nil, status: .missing(.calibrating), badge: .hide),
                ], editing: true, onBadge: { _ in }, onMove: { _, _ in }, onAdd: {})
                JISectionHeader("Signals")
                Surface {
                    VStack(spacing: 8) {
                        SignalRow(label: "Overnight HRV", value: 25, unit: "ms", status: .watch, detail: "threshold 27 ms")
                        SignalRow(label: "Sleep", value: 7.4, unit: "h", decimals: 1, status: .clear, detail: "floor 7.0 h")
                        SignalRow(label: "Resting HR", value: nil, unit: "bpm", status: .missing(.noData))
                    }
                }
                HStack { SyncedPill(date: today, now: today, calendar: calendar); SyncedPill(date: today.addingTimeInterval(-86_400), label: .lastSynced, now: today, calendar: calendar) }
                HowWeCalculate(title: JIExplainers.energyBalanceTitle, steps: JIExplainers.energyBalanceSteps, note: JIExplainers.energyBalanceNote)
            }
            .padding(16)
            .readableColumn()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(GalleryBackground())
    }
}

private struct GalleryBackground: ViewModifier {
    @Environment(\.jiTheme) private var theme
    func body(content: Content) -> some View { content.background(theme.color(.bg)) }
}

/// `preferredColorScheme` only when a segment asks for one; `nil` leaves the cell's scheme alone.
private struct OptionalColorScheme: ViewModifier {
    let scheme: ColorScheme?
    func body(content: Content) -> some View {
        if let scheme { content.environment(\.colorScheme, scheme) } else { content }
    }
}
