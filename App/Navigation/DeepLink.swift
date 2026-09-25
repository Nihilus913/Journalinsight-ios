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
    /// W-FIX2 fixer BUG-13: Today's full Trends screen. A path value (not a destination
    /// `NavigationLink`) so a KPI pushed from Trends stacks on top of it and Back returns to it —
    /// the path-bound stack dropped the non-path link on the router's push.
    case trends

    static func destination(for link: DeepLink) -> RootRoute? {
        switch link {
        case .gate: nil
        case .kpiDetail(let metric): .kpiDetail(metric: metric)
        }
    }
}

/// B-55 (P0 crash "tapping something too fast force-closes the app"): the per-tab push state
/// `RootTabView` binds each tab's own `NavigationStack(path:)` to. There is deliberately NO root
/// stack any more — the old shell wrapped the whole `TabView` in `NavigationStack(path: $path)`
/// while the search-role Tab (and More) ran their own nested stacks under it. Once the search Tab
/// had been mounted, EVERY change to that root bound path (a KPI push, and the pop back) trapped in
/// SwiftUI's `NavigationColumnState.boundPathChange` → `try!` →
/// `AnyNavigationPath.Error.comparisonTypeMismatch` (reproduced on the sim: Search → Today → tap a
/// KPI ring), and a push followed by a fast tab switch sent the nested `UINavigationController`s
/// into a content-inset layout loop (the phone's 0x8BADF00D hang-kill).
///
/// Every route has exactly one owning tab; a push lands in that tab's stack only, and a second
/// push onto the same tab inside `reentryInterval` (one push animation) is dropped, so a double
/// tap or two tiles hit back-to-back can never stack two appends inside one navigation update.
struct TabRouter: Equatable {
    /// Roughly one UIKit push animation (0.35 s) plus a frame of slack.
    static let reentryInterval: TimeInterval = 0.4

    private var paths: [RootTab: [RootRoute]] = [:]
    private var lastPush: [RootTab: Date] = [:]

    /// The tab a DEEP LINK's route is pushed onto (`ji://kpi-detail` focuses Today). A tap inside
    /// the app pushes on the tab it came from instead (`push(_:on:)`, W-FIX2 BUG-13).
    static func owner(of route: RootRoute) -> RootTab {
        switch route {
        case .kpiDetail, .kpiList, .trends: .today
        }
    }

    func path(for tab: RootTab) -> [RootRoute] { paths[tab] ?? [] }

    /// The stack's own writes (system back button, swipe-to-pop) come through here.
    mutating func setPath(_ path: [RootRoute], for tab: RootTab) {
        paths[tab] = path
    }

    /// W-FIX2 DEV-04: `ji://gate` shows Decide at the root of Today's stack.
    mutating func popToRoot(_ tab: RootTab) { paths[tab] = [] }

    /// Pushes `route` onto its owning tab's stack (the deep-link path).
    @discardableResult
    mutating func push(_ route: RootRoute, now: Date = Date()) -> Bool {
        push(route, on: Self.owner(of: route), now: now)
    }

    /// W-FIX2 BUG-13: pushes `route` onto `tab`'s stack — the tab the tap came from, so Back
    /// returns there (a Recovery tile's detail used to land on Today's stack). Returns false (and
    /// changes nothing) when the route is already on top, or when another push onto that tab is
    /// still in flight.
    @discardableResult
    mutating func push(_ route: RootRoute, on tab: RootTab, now: Date = Date()) -> Bool {
        guard path(for: tab).last != route else { return false }
        if let last = lastPush[tab], now.timeIntervalSince(last) < Self.reentryInterval, now >= last { return false }
        paths[tab, default: []].append(route)
        lastPush[tab] = now
        return true
    }
}
