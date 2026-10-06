import Foundation
import JICore

/// RG-80: every glance surface opens the matching screen on tap (a member of BOTH the app and the
/// widget targets so the app's `DeepLink.parse` tests pin the exact strings the widgets emit).
/// - Gate widget + verdict Live Activity → `ji://gate` (Decide on Today).
/// - KPI widget → `ji://kpi-detail?metric=<id>` for the configured metric.
nonisolated enum WidgetDeepLinks {
    static let gate = URL(string: "ji://gate")!

    static func kpiDetail(_ metric: KpiMetricId) -> URL {
        var c = URLComponents()
        c.scheme = "ji"; c.host = "kpi-detail"
        c.queryItems = [URLQueryItem(name: "metric", value: metric.rawValue)]
        return c.url!
    }
}
