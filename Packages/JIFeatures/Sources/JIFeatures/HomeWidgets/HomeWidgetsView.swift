import SwiftUI
import JICore
import JIDesign

// W-TGT fixer 1f (mock 05, spec §4) — Settings › Home & widgets: what Today shows and in which
// order. Cards (Today's cards, top to bottom) · On Today (the square picker, inline — the screen
// that was My KPIs) · Widgets & Live Activity. A square opens its detail, where the Targets card
// edits the goal.

/// One card of Today, in Today's order, with its state (Today's card order is fixed; the squares
/// are the part the user picks).
public nonisolated struct HomeWidgetsCard: Equatable, Sendable {
    public let title: String
    public let state: String
}

public nonisolated func homeWidgetsCards(squares: Int) -> [HomeWidgetsCard] {
    [HomeWidgetsCard(title: "Decide / Coach / Day", state: "always first"),
     HomeWidgetsCard(title: "Next session", state: "on"),
     HomeWidgetsCard(title: "Fuel today", state: "on"),
     HomeWidgetsCard(title: "Tonight", state: "on"),
     HomeWidgetsCard(title: "KPI squares", state: settingsKpisTrailing(squares)),
     HomeWidgetsCard(title: "Trends · Week review", state: "on")]
}

/// Settings root row subtitle (mock 04).
public nonisolated func homeWidgetsSubtitle(squares: Int) -> String {
    "Card order · \(squares) squares on Today · widgets · Live Activity"
}

public nonisolated struct HomeWidgetsRow: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let systemImage: String
}

public nonisolated let homeWidgetsRows: [HomeWidgetsRow] = [
    HomeWidgetsRow(title: "Lock-screen widget", subtitle: "readiness ring + 2 squares", systemImage: "lock.rectangle"),
    HomeWidgetsRow(title: "Workout Live Activity", subtitle: "session · live HR vs cap", systemImage: "waveform.path.ecg"),
]

public nonisolated let homeWidgetsSubtitleLine = "What Today shows and in which order"
public nonisolated let homeWidgetsCardsFooter = "Today's cards keep this order. The squares are yours: tick them below, or open KPI squares to drag them into order."
public nonisolated let homeWidgetsOnTodayCaption = "Today holds \(KpiSelection.minSelected) to \(KpiSelection.maxSelected) squares. Captions read Targets: \"goal\" is yours, \"your normal\" is computed. Tap a square for its detail; change a goal there or in Settings › Targets."

public struct HomeWidgetsView: View {
    @Environment(SettingsViewModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.jiOffscreenRender) private var offscreen
    private let theme = JITheme.native

    public init() {}

    public var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 0) {
                if jiTitleWrapsInList(typeSize) {
                    Text("Home & widgets").jiFont(.title, weight: .bold, tint: .text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, JISpacing.s4).padding(.bottom, JISpacing.s2)
                }
                Text(homeWidgetsSubtitleLine).jiFont(.subheadline, tint: .muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, JISpacing.s4)

                JISectionHeader("Cards")
                cardsCard
                footnote(homeWidgetsCardsFooter)

                if let kpis = model.kpiListModel {
                    KpiCatalogueGrids(model: kpis, onSelectKpi: model.kpiSelectAction)
                        .task { if !offscreen, !kpis.hasLiveResult { await kpis.load() } }
                        .accessibilityIdentifier("homeWidgets.onToday")
                } else {
                    footnote(settingsHubOnlySubtitle(action: "choose KPIs", hubConfigured: model.connection.host != nil,
                                                     dataSource: ProviderSwitch.shared.kind))
                        .accessibilityIdentifier("settings.row.onToday.unavailable")
                }
                footnote(homeWidgetsOnTodayCaption)

                JISectionHeader("Widgets & Live Activity")
                Surface(level: 1, padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(homeWidgetsRows.enumerated()), id: \.offset) { index, row in
                            if index > 0 { JIRowDivider() }
                            infoRow(title: row.title, subtitle: row.subtitle, systemImage: row.systemImage)
                        }
                    }
                    .padding(.horizontal, JISpacing.s4).padding(.vertical, 4)
                }
                footnote(settingsWidgetsHowTo)

                JISectionHeader("Fuel plan")
                Surface(level: 1, padding: 0) {
                    NavigationLink { WeeklyPlanView(model: model.makeWeeklyPlanModel()) } label: {
                        JIChevronRow(title: "Weekly kcal / macro plan", systemImage: "calendar")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, JISpacing.s4).padding(.vertical, 4)
                    .accessibilityIdentifier("homeWidgets.weeklyPlan")
                }
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
        .jiGlassBackButton()
        .jiTheme(.native)
        .navigationTitle("Home & widgets")
        #if os(iOS)
        .navigationBarTitleDisplayMode(jiTitleWrapsInList(typeSize) ? .inline : .automatic)
        #endif
        .navigationDestination(item: Binding(get: { model.kpiDetailMetric }, set: { model.kpiDetailMetric = $0 })) { metric in
            if let detail = model.kpiDetailModel, detail.metric == metric {
                KpiDetailView(model: detail)
            } else {
                ContentUnavailableView("KPI unavailable", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
    }

    private var cardsCard: some View {
        Surface(level: 1, padding: 0) {
            VStack(spacing: 0) {
                let cards = homeWidgetsCards(squares: model.kpiSelectedCount)
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    if index > 0 { JIRowDivider() }
                    if card.title == "KPI squares" {
                        NavigationLink {
                            EditTodayView(model: EditTodayViewModel(prefs: model.prefs, chips: model.todayChips()))
                        } label: {
                            JIChevronRow(title: card.title, value: card.state, systemImage: "square.grid.3x2")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("homeWidgets.editSquares")
                    } else {
                        HStack(spacing: JISpacing.s3) {
                            Text(card.title).jiFont(.body, tint: .text).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: JISpacing.s2)
                            Text(card.state).jiFont(.subheadline, tint: .muted)
                        }
                        .padding(.vertical, JISpacing.s3)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.horizontal, JISpacing.s4).padding(.vertical, 4)
        }
        .accessibilityIdentifier("homeWidgets.cards")
    }

    private func infoRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: JISpacing.s3) {
            Image(systemName: systemImage).foregroundStyle(theme.color(.info)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).jiFont(.body, tint: .text).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).jiFont(.caption, tint: .muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, JISpacing.s3)
        .accessibilityElement(children: .combine)
    }

    private func footnote(_ text: String) -> some View {
        Text(text).jiFont(.caption, tint: .muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s2)
    }
}
