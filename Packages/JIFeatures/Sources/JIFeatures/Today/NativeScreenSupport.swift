import SwiftUI
import Foundation
import JICore
import JIPersistence

// MARK: - B-33 §8.5 offscreen rendering

/// True while the screen is being drawn by the `ScreenRegistry` sweep through `ImageRenderer`.
/// `ImageRenderer` lays a `ScrollView` out but never renders its *content* off-screen, so a
/// sweep PNG of a scrolling screen comes back as a bare background. Screens therefore wrap their
/// body in `ScreenScroll`, which drops to a plain stack while this is set.
struct JIOffscreenRenderKey: EnvironmentKey { nonisolated static let defaultValue = false }

public extension EnvironmentValues {
    /// B-33 §8.5 — see `JIOffscreenRenderKey`. Public so the sweep can set it; never read by app code.
    var jiOffscreenRender: Bool {
        get { self[JIOffscreenRenderKey.self] }
        set { self[JIOffscreenRenderKey.self] = newValue }
    }
}

/// The vertical scroll container every B-33 hero screen uses. Identical to `ScrollView` in the
/// app; a plain top-aligned stack under `jiOffscreenRender` so the sweep captures real content.
public struct ScreenScroll<Content: View>: View {
    private let content: Content
    @Environment(\.jiOffscreenRender) private var offscreen

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        if offscreen {
            // Pinned to the cell and clipped from the TOP: a screen taller than the cell used to
            // overflow symmetrically (the sweep showed its middle), and a bottom overlay (W-B57b
            // Coach card) sat off-cell. Now the cell shows what a phone shows before scrolling.
            GeometryReader { g in
                VStack(spacing: 0) { content; Spacer(minLength: 0) }
                    .frame(width: g.size.width, alignment: .top)
                    .frame(height: g.size.height, alignment: .top)
                    .clipped()
            }
        } else {
            // `.refreshable` at the call site lands on this `ScrollView` through the environment.
            ScrollView { content }
        }
    }
}

// MARK: - Fixture plumbing

/// One in-memory database backing every fixture view model (§8.5: the registry is fixture-backed,
/// never hub-backed). `nil` only if SQLite itself cannot open in memory, which the fixtures treat
/// as "render the empty state" rather than trapping inside a test run.
@MainActor enum NativeFixtureStore {
    static let database: AppDatabase? = try? AppDatabase.inMemory()
    static var cache: OfflineCache? { database.map(OfflineCache.init(db:)) }
    static var prefs: PrefStore? { database.map(PrefStore.init(db:)) }

    /// Decodes a wire-format literal with the hub's own decoder. Fixture DTOs (`MorningResponse`,
    /// `GateResponse`) have internal memberwise inits, so JSON is the only way to build one here.
    static func decode<T: Decodable>(_ json: String, as type: T.Type) -> T? {
        try? JSON.decoder.decode(T.self, from: Data(json.utf8))
    }
}

// MARK: - Registry-facing screens (B-33 lane L4)

/// Wraps a fixture-backed screen for the sweep: the native language plus the offscreen flag, so
/// `ImageRenderer` captures real content. Deliberately NOT inside a `NavigationStack` — a
/// navigation stack schedules work of its own after each render pass, and `ImageRenderer` has no
/// update to attach it to on the next cell ("no current update to enqueue action to"). The
/// navigation chrome (`.navigationTitle`, `.navigationDestination`) is exercised in the app and
/// by the sim smoke, never by the sweep.
struct NativeScreenPreview<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .jiTheme(.native)
            .environment(\.jiOffscreenRender, true)
    }
}

/// Rule 5: a fixture that cannot be built renders the screen's own unavailable state, never a
/// blank sweep cell.
struct NativeFixtureUnavailable: View {
    let screen: String
    var body: some View {
        ContentUnavailableView {
            Label("\(screen) fixture unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text("The in-memory fixture store could not be opened.")
        }
    }
}

/// The five screens lane L4 registers. Each builds its own view model from literals — no hub,
/// no disk, no async load — so the §8.5 sweep renders the same pixels on every run.
@MainActor enum L4Screens {
    static func today() -> AnyView {
        guard let model = TodayViewModel.fixture() else { return AnyView(NativeFixtureUnavailable(screen: "Today")) }
        return AnyView(NativeScreenPreview { TodayView(model: model, onOpenConnection: {}) })
    }

    // B-57: the three morning faces, each over the same loaded fixture pinned to one state.
    static func todayDecide() -> AnyView { todayMorning(.decide, screen: "Today decide") }
    static func todayCoach() -> AnyView { todayMorning(.coach, screen: "Today coach") }
    static func todayDay() -> AnyView { todayMorning(.day, screen: "Today day") }
    /// B-65: Decide on an Apple Watch night — shows the muted `context` arc (daytime HRV).
    static func todayDecideApple() -> AnyView { todayMorning(.decide, screen: "Today decide Apple", morningJSON: fixtureMorningAppleJSON) }

    private static func todayMorning(_ state: TodayMorningState, screen: String, morningJSON: String? = nil) -> AnyView {
        guard let model = TodayViewModel.fixture(morningState: state, morningJSON: morningJSON) else { return AnyView(NativeFixtureUnavailable(screen: screen)) }
        // W-B57b: an override model over the in-memory store, so Decide shows Go AND Adjust.
        return AnyView(NativeScreenPreview {
            TodayView(model: model, onOpenConnection: {})
                .environment(\.verdictOverrideModel, fixtureOverrideModel())
        })
    }

    /// W-B57b (B-62): the Adjust sheet's form over the Decide fixture's verdict, a choice and a
    /// reason already picked so the sweep shows the selected state.
    static func todayAdjust() -> AnyView {
        guard let morning = TodayViewModel.fixture(morningState: .decide)?.morning else {
            return AnyView(NativeFixtureUnavailable(screen: "Today adjust"))
        }
        return AnyView(NativeScreenPreview {
            ScreenScroll {
                VerdictAdjustForm(verdict: verdictParts(morning.verdict), sessionForToday: morning.sessionForToday,
                                  model: fixtureOverrideModel(), initialChoice: .full,
                                  initialReason: GateRespondCopy.overrideReasons.first) { _, _ in }
                    .padding(20)
            }
        })
    }

    private static func fixtureOverrideModel() -> VerdictOverrideViewModel? {
        NativeFixtureStore.database.map { VerdictOverrideViewModel(provider: MockDataProvider(), outbox: Outbox(db: $0)) }
    }

    static func recovery() -> AnyView {
        guard let model = RecoveryViewModel.fixture() else { return AnyView(NativeFixtureUnavailable(screen: "Recovery")) }
        return AnyView(NativeScreenPreview { RecoveryView(model: model) })
    }

    static func readinessRationale() -> AnyView {
        AnyView(NativeScreenPreview { GateRationaleView(model: GateRationaleViewModel.fixture()) })
    }

    static func gateConfig() -> AnyView {
        guard let model = GateConfigViewModel.fixture() else { return AnyView(NativeFixtureUnavailable(screen: "Gate config")) }
        return AnyView(NativeScreenPreview { GateConfigView(model: model) })
    }

    static func editToday() -> AnyView {
        AnyView(NativeScreenPreview { EditTodayView(model: EditTodayViewModel(prefs: NativeFixtureStore.prefs)) })
    }
}
