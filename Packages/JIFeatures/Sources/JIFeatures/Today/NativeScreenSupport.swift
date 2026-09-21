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
            VStack(spacing: 0) { content; Spacer(minLength: 0) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

}
