import SwiftUI
import UserNotifications
import JICore
import JIDesign
import JIFeatures
import JIHub
import JIPersistence

@main
struct JournalInsightApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // W2c-L4: owns the notification center delegate for this wave's single local notification
    // (LocalVerdictFloor's 05:10 floor reminder). Held as a `@State` reference type (not a local)
    // so it outlives the `.task` below and stays alive for `UNUserNotificationCenter.current().delegate`,
    // which holds it weakly.
    @State private var notificationDelegate = NotificationRoutingDelegate()
    // Built in `init()` (see its doc comment) — needs to happen there now alongside
    // `outboxRetry`'s construction so both respect struct definite-initialization order.
    @State private var env: AppEnvironment

    // Held by the App struct (not RootTabView's own @State) so a cold-start deep link — the
    // Info.plist-registered `ji`/`journalinsight` URL types resolve to `.onOpenURL` before
    // RootTabView has necessarily finished its first `.task` — has somewhere durable to land;
    // RootTabView reads it via `.onChange` and clears it once handled so re-opening the app
    // without a new URL doesn't replay a stale one.
    @State private var pendingDeepLink: DeepLink?

    // W7-L4 (P-hub-watchdog). Rebuilt on each `.active` transition rather than held for the app's
    // lifetime: `AppEnvironment.apply(_:)` swaps `providerStore.provider` whenever the connection
    // changes, and a watchdog pinned to a stale provider would be probing a hub the app no longer
    // uses. Torn down on background — probing from behind the lock screen tells nobody anything.
    @Environment(\.scenePhase) private var scenePhase
    @State private var watchdog: HubWatchdog?

    // W8-L4 (P-hub-watchdog debt): periodic foreground retry + BG-refresh for anything the outbox
    // still holds (gate-respond/feel rows the in-tap attempt and the watchdog's reachable-again
    // drain didn't clear). `drainerSource` is resolved lazily — same reasoning as `makeWatchdog`,
    // no hub provider exists before a connection does; `capturedEnv` below is the same
    // `AppEnvironment` reference `env` holds (a class), so it always sees the current
    // `providerStore` even though the closure is built once in `init()`.
    @State private var outboxRetry: OutboxRetryScheduler

    // W-FIX2 BUG-15: the Appearance choice (mode, accent, text size), read from `PrefStore` at
    // launch and live after every Appearance save. Replaces the unconditional `.dark`.
    @State private var theme: AppThemeModel

    // CODE-2: a boot-time Keychain READ error (e.g. transient Secure Enclave/first-unlock failure)
    // must not crash launch — treat it like "no token yet" and let RootTabView present the
    // Connection sheet (env.needsConnection) instead. Only a failure to construct the environment
    // itself (cache/prefs storage) is still fatal.
    init() {
        let builtEnv: AppEnvironment = {
            do {
                let e = try AppEnvironment()
                do { try e.boot() } catch { e.needsConnection = true }
                return e
            } catch { fatalError("AppEnvironment init failed: \(error)") }
        }()
        _env = State(initialValue: builtEnv)
        _theme = State(initialValue: AppThemeModel(prefs: builtEnv.prefs))

        let scheduler = OutboxRetryScheduler(
            drainerSource: {
                guard let provider = builtEnv.providerStore?.provider,
                      let outbox = try? Outbox(db: .onDisk()) else { return nil }
                return OutboxDrainer(outbox: outbox, hub: provider)
            },
            background: BGTaskSchedulerAdapter()
        )
        // BGTaskScheduler requires registration before launch finishes.
        scheduler.registerBackgroundTask()
        _outboxRetry = State(initialValue: scheduler)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(env: env, pendingDeepLink: $pendingDeepLink)
                // W-FIX2 BUG-15: system / Light / Dark from Appearance, set as the window override
                // (`.unspecified` = follow the device). Not `.preferredColorScheme`: once forced, its
                // nil does not reliably hand the window back to the system.
                .onChange(of: theme.mode, initial: true) { _, _ in theme.applyToWindows() }
                .tint(theme.accent)
                .dynamicTypeSize(theme.dynamicTypeRange)
                .onOpenURL { url in
                    guard let link = DeepLink.parse(url) else { return }
                    pendingDeepLink = link
                }
                .task {
                    // W2c-L4: a tapped notification (LocalVerdictFloor's 05:10 floor reminder)
                    // lands on the SAME `pendingDeepLink` seam `.onOpenURL` uses above, so
                    // RootTabView's single `.onChange`/`.onAppear` pair (see its doc comment)
                    // handles both sources identically — no second navigation path to keep in sync.
                    notificationDelegate.onDeepLink = { link in pendingDeepLink = link }
                    #if DEBUG
                    // W-FIX3 fixer C-h: `-JISeedRMSSD <ms>` — the simulator's live-record RMSSD writer.
                    await DebugRmssdSeeder.seedIfRequested()
                    #endif
                    UNUserNotificationCenter.current().delegate = notificationDelegate
                    // W-B47 (L2), same affordance as B-46's `-no-healthkit` above it in
                    // `AppEnvironment.boot()`: `-no-push` suppresses the cold-start notification
                    // prompt. The build host has no Simulator UI, so a system alert on top of
                    // Today cannot be dismissed and every scripted screenshot of a live-hub run
                    // would be taken through it.
                    guard !CommandLine.arguments.contains("-no-push") else { return }
                    do {
                        _ = try await UNUserNotificationCenter.current()
                            .requestAuthorization(options: [.alert, .sound, .badge])
                        try await LocalVerdictFloor.schedule()
                    } catch {
                        // Authorization denied or scheduling failed — the floor reminder is a
                        // nudge, not a data path; the app must keep working without it.
                    }
                    // W7-L2 (P-apns-push): re-register this device's APNs token on every cold
                    // launch, reusing the single authorization request above rather than prompting
                    // again. The provider is resolved lazily because `env.providerStore` doesn't
                    // exist until a hub connection does (first run shows the Connection sheet).
                    // Registration is additive to ntfy and never fatal — a Simulator launch simply
                    // logs `.unavailable` (see `ApnsRegistration`).
                    ApnsRegistration.shared.providerSource = { [weak env] in
                        env?.providerStore?.provider as? any PushTokenProviding
                    }
                    await ApnsRegistration.shared.registerOnLaunch()
                }
                // The single scene-phase site (W7-L4). `initial: true` so a cold launch counts as
                // the first foreground and the app learns whether the hub is there before the user
                // has to find out from a blank screen.
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active {
                        watchdog = makeWatchdog()
                        watchdog?.start()
                        outboxRetry.startForeground()
                        env.foregroundHealthUpload() // B-65: last night reaches the hub on open
                    } else {
                        watchdog?.stop()
                        watchdog = nil
                        outboxRetry.stopForeground()
                    }
                }
        }
    }

    /// Builds a watchdog over the CURRENT provider, with the outbox recovery drain hooked to its
    /// reachable-again transition. `nil` before a connection exists (`needsConnection`) — there is
    /// no hub to probe yet, and `ConnectionSheet` is the honest surface for that, not a banner.
    @MainActor
    private func makeWatchdog() -> HubWatchdog? {
        guard let provider = env.providerStore?.provider else { return nil }
        let watchdog = HubWatchdog(provider: provider)
        // W8-L4: drain every kind this hub can deliver (weigh-in + gate-respond/feel), not just
        // weigh-in — `OutboxDrainer(hub:)` picks up whichever provider protocols `provider`
        // actually conforms to and leaves the rest untouched.
        if let outbox = try? Outbox(db: .onDisk()) {
            let drainer = OutboxDrainer(outbox: outbox, hub: provider)
            watchdog.onReachableAgain = { await drainer.drainOnForeground() }
        }
        return watchdog
    }
}
