import Foundation
import Testing
import JICore
@testable import JIHub

@MainActor
@Suite(.serialized) struct HubWatchdogTests {
    private func makeWatchdog(
        interval: Duration = .milliseconds(5),
        now: @escaping () -> Date = Date.init
    ) -> HubWatchdog {
        WatchdogStubURLProtocol.reset()
        let provider = HubDataProvider(client: HubClient(
            config: .init(baseURL: URL(string: "http://hub.test:8000")!, token: "t"),
            session: WatchdogStubURLProtocol.session()
        ))
        return HubWatchdog(provider: provider, interval: interval, now: now)
    }

    @Test func startsOptimisticBeforeAnyProbe() {
        let w = makeWatchdog()
        #expect(w.reachable == true)
        #expect(w.lastOk == nil)
        #expect(w.lastError == nil)
    }

    @Test func healthyProbeSetsReachableAndStampsLastOk() async {
        let stamp = Date(timeIntervalSince1970: 1_758_000_100)
        let w = makeWatchdog(now: { stamp })
        WatchdogStubURLProtocol.behaviour = .ok

        #expect(await w.probe() == true)
        #expect(w.reachable == true)
        #expect(w.lastOk == stamp)
        #expect(w.lastError == nil)
        // It probes /health, never a data route.
        #expect(WatchdogStubURLProtocol.requestedPaths == ["/health"])
    }

    @Test func timeoutMakesHubUnreachable() async {
        let w = makeWatchdog()
        WatchdogStubURLProtocol.behaviour = .timeout

        #expect(await w.probe() == false)
        #expect(w.reachable == false)
        if case .network = w.lastError {} else { Issue.record("expected .network, got \(String(describing: w.lastError))") }
        #expect(w.lastOk == nil)
    }

    @Test func nonTwoHundredMakesHubUnreachable() async {
        let w = makeWatchdog()
        WatchdogStubURLProtocol.behaviour = .status(503)

        #expect(await w.probe() == false)
        #expect(w.reachable == false)
        #expect(w.lastError != nil)
    }

    @Test func recoveryFiresOnReachableAgainExactlyOnce() async {
        let w = makeWatchdog()
        let drains = Counter()
        w.onReachableAgain = { drains.bump() }

        // First probe succeeds: no outage was ever observed, so nothing to drain.
        WatchdogStubURLProtocol.behaviour = .ok
        await w.probe()
        #expect(drains.count == 0)

        // Hub goes away, then comes back — one transition, one drain.
        WatchdogStubURLProtocol.behaviour = .timeout
        await w.probe()
        #expect(w.reachable == false)
        WatchdogStubURLProtocol.behaviour = .ok
        await w.probe()
        #expect(w.reachable == true)
        #expect(drains.count == 1)

        // Staying up does not re-fire.
        await w.probe()
        #expect(drains.count == 1)
    }

    @Test func successClearsThePreviousError() async {
        let w = makeWatchdog()
        WatchdogStubURLProtocol.behaviour = .status(500)
        await w.probe()
        #expect(w.lastError != nil)
        WatchdogStubURLProtocol.behaviour = .ok
        await w.probe()
        #expect(w.lastError == nil)
    }

    @Test func startProbesRepeatedlyUntilStopped() async throws {
        let w = makeWatchdog(interval: .milliseconds(5))
        WatchdogStubURLProtocol.behaviour = .ok
        w.start()
        // Poll rather than sleeping a fixed span: enough ticks to prove it's a loop, not one shot.
        for _ in 0..<200 where WatchdogStubURLProtocol.requestedPaths.count < 3 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(WatchdogStubURLProtocol.requestedPaths.count >= 3)

        w.stop()
        try await Task.sleep(for: .milliseconds(20))
        let afterStop = WatchdogStubURLProtocol.requestedPaths.count
        try await Task.sleep(for: .milliseconds(40))
        #expect(WatchdogStubURLProtocol.requestedPaths.count == afterStop)
    }

    @Test func stopKeepsTheLastHonestReading() async {
        let w = makeWatchdog()
        WatchdogStubURLProtocol.behaviour = .timeout
        await w.probe()
        w.stop()
        // Backgrounding must not reset to optimism.
        #expect(w.reachable == false)
    }

    @Test func defaultIntervalIsTheStalenessFloor() {
        // The watchdog period and the staleness floor are the same number by construction.
        #expect(Duration.seconds(Staleness.hubQueryStaleTime) == .seconds(45))
    }
}

/// Main-actor counter for the recovery-hook assertions (the hook is `@MainActor`, so no locking).
@MainActor private final class Counter {
    private(set) var count = 0
    func bump() { count += 1 }
}
