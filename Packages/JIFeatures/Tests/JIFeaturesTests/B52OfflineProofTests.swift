import Foundation
import Testing
import ImageIO
import UniformTypeIdentifiers
import SwiftUI
import QuartzCore
import JICore
import JIHub
import JIPersistence
import JIDesign
@testable import JIFeatures
#if canImport(UIKit)
import UIKit
#endif

// B-52 offline proof (W-B41 L2 exit). This is the round trip the Wave Card asks for, run on the
// simulator against the REAL hub: queue a weekday while the hub is unreachable, screenshot the
// assignment standing with its pending marker, then point at the live hub, drain, and screenshot
// the marker cleared.
//
// It is opt-in — `JI_B52_PROOF_DIR` (plus `JI_B52_HUB_URL` / `JI_B52_HUB_TOKEN`) must be set, or
// the test returns without touching the network. A test in the default suite must never depend on
// Toby's hub being up, and must never write to it.

#if canImport(UIKit) && !os(watchOS)

@MainActor
private func proofImage(_ view: some View, height: CGFloat = 1700) -> CGImage? {
    // Exactly `ScreenSweepTests.sweepImage`'s route, at the 393 pt iPhone width: a real window
    // (never `makeKeyAndVisible` — no host app here), a run-loop turn and a `CATransaction.flush`
    // so the off-screen layer tree actually has contents, then `drawHierarchy` with a
    // `layer.render` fallback. Skipping any of that is what renders a blank page.
    let bounds = CGRect(x: 0, y: 0, width: 393, height: height)
    let host = UIHostingController(rootView: view.jiTheme(.native).jiRevealAnimations(false))
    host.view.frame = bounds
    host.view.backgroundColor = .systemBackground
    host.traitOverrides.userInterfaceStyle = .dark
    host.traitOverrides.horizontalSizeClass = .compact
    host.traitOverrides.verticalSizeClass = .regular

    let window = UIWindow(frame: bounds)
    window.overrideUserInterfaceStyle = .dark
    window.rootViewController = host
    window.isHidden = false

    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    CATransaction.flush()

    let format = UIGraphicsImageRendererFormat()
    format.scale = 2
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { ctx in
        if !host.view.drawHierarchy(in: bounds, afterScreenUpdates: true) {
            host.view.layer.render(in: ctx.cgContext)
        }
    }
    window.isHidden = true
    window.rootViewController = nil
    return image.cgImage
}

@MainActor
private func writePNG(_ image: CGImage?, to url: URL) {
    guard let image,
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { Issue.record("could not render \(url.lastPathComponent)"); return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}


/// `today` shifted by `offsetDays`, in the UTC calendar the day keys use.
private func dateString(offsetDays: Int, from today: String) -> String? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    guard let date = formatter.date(from: today),
          let shifted = calendar.date(byAdding: .day, value: offsetDays, to: date) else { return nil }
    return formatter.string(from: shifted)
}

@Test @MainActor func b52OfflineThenOnlineRoundTripAgainstTheLiveHub() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let dir = env["JI_B52_PROOF_DIR"],
          let hubURL = env["JI_B52_HUB_URL"].flatMap(URL.init(string:)),
          let token = env["JI_B52_HUB_TOKEN"]
    else { return }   // opt-in only — see the file comment
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

    let live = HubDataProvider(client: HubClient(config: ConnectionConfig(baseURL: hubURL, token: token)))
    // Port 9 (discard) never answers: the app's own "no internet" for the length of this test.
    let dead = HubDataProvider(client: HubClient(config: ConnectionConfig(baseURL: URL(string: "http://127.0.0.1:9")!, token: "x")))

    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let defaults = UserDefaults(suiteName: "b52.proof.\(UUID().uuidString)")!

    @MainActor func makeVM(_ provider: any TrainingProviding & Sendable) -> TrainingViewModel {
        TrainingViewModel(
            provider: provider, healthProvider: live, cache: cache,
            strengthStore: StrengthStateStore(defaults: defaults),
            outbox: outbox, drainer: OutboxDrainer(outbox: outbox, hub: provider)
        )
    }

    // 1. One online load, so the cache holds the real plan — this is the state the phone is in
    //    when it goes offline.
    let online = makeVM(live)
    await online.load()
    try #require(!online.planSessions.isEmpty, "the hub returned no plan sessions — cannot prove anything")
    // The REAL plan-session id comes from the day detail's `planned_session`: this hub's
    // `/planning/exercises` rows carry no `session_id` (checked 2026-09-22), so the spine derived
    // from them holds the week strip's `exercise_id` fallback, which the PUT route 404s on.
    // Of this week's planned sessions we take the first one that ALSO has exercise rows, because
    // those rows' `weekday` (joined server-side from `plan.plan_session`) is the unambiguous
    // witness that the write landed — `/training/day/{date}` cannot be, since every weekday on
    // this plan is already occupied and its lookup returns only one session per day.
    let today = String(Date().ISO8601Format().prefix(10))
    var found: PlannedSession?
    for offset in 0..<7 {
        guard let date = dateString(offsetDays: offset, from: today),
              let planned = try await live.trainingDay(date: date).plannedSession,
              online.exercises.contains(where: { $0.sessionName == planned.name })
        else { continue }
        found = planned
        break
    }
    let planned = try #require(found, "no planned session this week has exercise rows to witness with")
    let session = PlanSessionOut(id: planned.id, name: planned.name, weekday: planned.weekday)
    let originalWeekday = session.weekday
    let queuedWeekday = (originalWeekday == 4) ? 5 : 4   // any weekday that is NOT the current one

    // 2. Offline: assign a weekday with the hub unreachable.
    let offline = makeVM(dead)
    await offline.load()
    await offline.assignSession(sessionId: session.id, sessionName: session.name, weekday: queuedWeekday)
    #expect(offline.pendingSessionSync.contains(session.id))
    #expect(offline.sessionAssignFailed.isEmpty)
    #expect(offline.planSessions.first(where: { $0.id == session.id })?.weekday == queuedWeekday)
    #expect(try outbox.pending().filter { $0.kind == OutboxDrainer.planWeekdayKind }.count == 1)
    writePNG(proofImage(NavigationStack { TrainingView(model: offline) }), to: out.appending(path: "b52-offline-pending.png"))

    // 3. Back online: the watchdog's own drainer lands the row; this screen only re-reads the queue.
    let backOnline = makeVM(live)
    await backOnline.load()
    let watchdogDrainer = OutboxDrainer(outbox: outbox, hub: live)
    let results = await watchdogDrainer.drainOnForeground()
    #expect(results.values.contains { if case .success(.planWeekday) = $0 { return true }; return false })
    backOnline.reconcilePendingSync()
    await backOnline.refresh()
    #expect(backOnline.pendingSessionSync.isEmpty)
    #expect(try outbox.pending().filter { $0.kind == OutboxDrainer.planWeekdayKind }.isEmpty)
    // The hub itself now says so — not just the screen: the RE-FETCHED plan rows carry the new
    // weekday, which the hub joins from `plan.plan_session`.
    #expect(backOnline.exercises.first(where: { $0.sessionName == session.name })?.weekday == queuedWeekday)
    writePNG(proofImage(NavigationStack { TrainingView(model: backOnline) }), to: out.appending(path: "b52-online-cleared.png"))

    // 4. Put Toby's plan back exactly as it was — a proof must not leave a change behind.
    _ = try? await live.updatePlanSessionWeekday(sessionId: session.id, weekday: originalWeekday)
}

#endif
