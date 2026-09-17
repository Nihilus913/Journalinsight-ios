import Foundation

/// W2b-L3 deep links. Accepts both `ji://` and `journalinsight://` schemes (the URL types
/// registered in project.yml's `CFBundleURLTypes`). Parsing is host-vs-path robust: a URL like
/// `ji://gate` puts "gate" in `.host`, but some hand-typed/share-sheet URLs collapse to
/// `ji:gate` or `ji:///gate` (no host, "gate" in `.path`) — both shapes resolve the same way.
enum DeepLink: Hashable, Sendable {
    case gate
    case kpiDetail(metric: String)

    static func parse(_ url: URL) -> DeepLink? {
        guard let scheme = url.scheme?.lowercased(), scheme == "ji" || scheme == "journalinsight" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        let host = (components.host ?? "").lowercased()
        let pathSegments = components.path.split(separator: "/").map(String.init)
        let identifier = !host.isEmpty ? host : (pathSegments.first ?? "")

        switch identifier {
        case "gate":
            return .gate
        case "kpi-detail":
            guard let metric = components.queryItems?.first(where: { $0.name == "metric" })?.value, !metric.isEmpty else { return nil }
            return .kpiDetail(metric: metric)
        default:
            return nil
        }
    }
}

/// Pure mapping seam from a parsed `DeepLink` to the value pushed onto `RootTabView`'s
/// `NavigationPath` — kept separate from any SwiftUI state so it's testable without a live UI
/// tap (`.gate` has no detail push yet; it only needs the Today tab focused, handled by the
/// caller). `RootRoute` conforms to `Hashable` so it can be used directly as a
/// `navigationDestination(for:)` value.
enum RootRoute: Hashable, Sendable {
    case kpiDetail(metric: String)
    /// W3b-L2 — the "My KPIs" list/picker. Reachable only from `RootTabView`'s toolbar (no deep
    /// link maps to it; the oracle's `app/kpis.tsx` isn't itself deep-linkable either).
    case kpiList

    static func destination(for link: DeepLink) -> RootRoute? {
        switch link {
        case .gate: nil
        case .kpiDetail(let metric): .kpiDetail(metric: metric)
        }
    }
}
