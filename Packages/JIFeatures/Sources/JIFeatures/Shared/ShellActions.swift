import SwiftUI

/// B-57 W1: shell navigation a screen can ask for without knowing the App's router. Set once by
/// `RootTabView` (L5); `nil` = the screen hides the control (a sweep render, a test host).
public extension EnvironmentValues {
    /// Opens the KPI catalogue (the App's "My KPIs" sheet). Recovery's "+ Add a metric".
    @Entry var openKpiCatalogue: (@MainActor @Sendable () -> Void)? = nil
    /// Pushes a KPI's detail by `KpiMetricId.rawValue`. Recovery tile taps.
    @Entry var openKpiDetail: (@MainActor @Sendable (String) -> Void)? = nil
}
