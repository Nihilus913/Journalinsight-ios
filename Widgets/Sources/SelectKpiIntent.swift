import AppIntents
import JICore
import WidgetKit

/// W-B34 (B-36): one pickable KPI for the configurable KPI widget. The id is
/// `KpiMetricId.rawValue`, so the choice survives relabelling and never matches on label text.
/// This is a *configuration* entity — the backlog's "interactive intents REJECTED" note concerns
/// action intents (buttons that do work) and stays true.
nonisolated struct KpiEntity: AppEntity {
    let id: String

    init(_ metric: KpiMetricId) { self.id = metric.rawValue }

    /// The typed metric; an unknown raw value (a KPI removed from the catalog after the user
    /// picked it) falls back to readiness rather than rendering nothing.
    var metric: KpiMetricId { KpiMetricId(rawValue: id) ?? .readiness }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "KPI"
    static let defaultQuery = KpiEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(KpiMetrics.def(metric).label)")
    }
}

/// Static, in-process catalog query — enumerates `KpiMetricId.allCases`, never the network.
nonisolated struct KpiEntityQuery: EntityQuery {
    func entities(for identifiers: [KpiEntity.ID]) async throws -> [KpiEntity] {
        identifiers.compactMap { KpiMetricId(rawValue: $0).map(KpiEntity.init) }
    }

    func suggestedEntities() async throws -> [KpiEntity] {
        KpiMetricId.allCases.map(KpiEntity.init)
    }

    /// The pre-selected choice when the widget is first added.
    func defaultResult() async -> KpiEntity? { KpiEntity(.readiness) }
}

/// Widget configuration: which single KPI the `KpiWidget` shows.
struct SelectKpiIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose KPI"
    static let description = IntentDescription("Pick the metric this widget shows.")

    @Parameter(title: "KPI")
    var kpi: KpiEntity?

    init() {}

    init(kpi: KpiMetricId) { self.kpi = KpiEntity(kpi) }

    /// The chosen metric; readiness when unset (the default).
    var metric: KpiMetricId { kpi?.metric ?? .readiness }
}
