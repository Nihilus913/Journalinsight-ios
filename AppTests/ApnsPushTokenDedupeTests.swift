import Foundation
import Testing
import JICore
@testable import JournalInsight

// RG-81 (B-21): the push token is POSTed only when it changed since the last hub ACK (it was
// re-POSTed on every launch — 33x in one regression run), and never under `-no-push`.
@Suite struct ApnsPushTokenDedupeTests {
    final class Spy: PushTokenProviding, @unchecked Sendable { // @unchecked: mutated only on the test's MainActor task
        var posts: [PushTokenRegistration] = []
        func registerPushToken(_ registration: PushTokenRegistration) async throws -> PushTokenAck {
            posts.append(registration)
            return PushTokenAck(ok: true, registeredAt: "2026-10-06T08:00:00Z")
        }
    }

    func freshDefaults() -> UserDefaults {
        let name = "rg81-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @MainActor @Test func unchangedTokenIsNotRepostedAcrossLaunches() async {
        let defaults = freshDefaults(), spy = Spy()
        let launch1 = ApnsRegistration(defaults: defaults)
        launch1.providerSource = { spy }
        await launch1.receive(deviceToken: Data([0xab, 0xcd]))
        #expect(spy.posts.count == 1)
        // Cold launch 2 + 3: same token → no POST.
        for _ in 0..<2 {
            let next = ApnsRegistration(defaults: defaults)
            next.providerSource = { spy }
            await next.receive(deviceToken: Data([0xab, 0xcd]))
            guard case .registered = next.state else { Issue.record("unchanged token must still read registered"); return }
        }
        #expect(spy.posts.count == 1)
        // A rotated token is POSTed.
        let rotated = ApnsRegistration(defaults: defaults)
        rotated.providerSource = { spy }
        await rotated.receive(deviceToken: Data([0x01, 0x02]))
        #expect(spy.posts.count == 2 && spy.posts.last?.token == "0102")
    }

    @MainActor @Test func aNewStartTokenIsAChange() async {
        let spy = Spy()
        let r = ApnsRegistration(defaults: freshDefaults())
        r.providerSource = { spy }
        await r.receive(deviceToken: Data([0xab]))
        await r.receive(liveActivityStartToken: Data([0x0f]))
        #expect(spy.posts.count == 2 && spy.posts.last?.liveActivityStartToken == "0f")
    }

    @MainActor @Test func noPushNeverPosts() async {
        let spy = Spy()
        let r = ApnsRegistration(defaults: freshDefaults(), pushDisabled: true)
        r.providerSource = { spy }
        await r.receive(deviceToken: Data([0xab, 0xcd]))
        await r.receive(liveActivityStartToken: Data([0x0f]))
        await r.retryPendingRegistration()
        #expect(spy.posts.isEmpty)
        #expect(r.pendingRegistration == nil)
    }
}
