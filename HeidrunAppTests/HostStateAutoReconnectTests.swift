import Foundation
import Testing
@testable import Heidrun
import CommonTools
import HeidrunCore
import HeidrunBookmarks

@MainActor
@Suite("HostState auto-reconnect")
struct HostStateAutoReconnectTests {

    /// Settings + scratch `UserDefaults` factory mirrored on `HostStateTests`'
    /// existing pattern (UUID-suffixed suite, scratched in teardown).
    private struct Scratch {
        let defaults: UserDefaults
        let suite: String

        init() {
            let suiteName = "HostStateAutoReconnectTests-\(UUID().uuidString)"
            self.defaults = UserDefaults(suiteName: suiteName)!
            self.defaults.removePersistentDomain(forName: suiteName)
            self.suite = suiteName
        }

        func teardown() { defaults.removePersistentDomain(forName: suite) }
    }

    private func makeSettings(_ name: String = "Test") -> ConnectionSettings {
        ConnectionSettings(
            name: name,
            address: "sample.example.com",
            port: 5500,
            nickname: "tester"
        )
    }

    private func makeCoordinator(
        defaults: UserDefaults,
        bookmark: Bookmark? = nil,
        sleep: @escaping @Sendable (Duration) async -> Void = { _ in }
    ) -> AutoReconnectCoordinator {
        AutoReconnectCoordinator(
            settingsProvider: { AutoReconnectGlobalSettings.live(defaults: defaults) },
            bookmarkLookup: { _ in bookmark },
            sleep: sleep
        )
    }

    @Test("unexpected disconnect with policy ON transitions to .connecting (not .failed)")
    func unexpectedDisconnectTriggersReconnect() async {
        let scratch = Scratch()
        defer { scratch.teardown() }
        scratch.defaults.set(true, forKey: AppStorageKeys.autoReconnectEnabled)
        scratch.defaults.set(3, forKey: AppStorageKeys.autoReconnectMaxAttempts)
        scratch.defaults.set(0, forKey: AppStorageKeys.autoReconnectDelaySeconds)

        // First connector call returns a fake whose stream we drive; second
        // call (the reconnect) returns a second fake that signals success.
        let firstFake = FakeHotlineClient()
        let secondFake = FakeHotlineClient()
        let nextClients = Mutex<[FakeHotlineClient]>([firstFake, secondFake])

        let coordinator = makeCoordinator(defaults: scratch.defaults)
        let state = makeTestHostState(
            connector: { _, _, _ in
                var clients = nextClients.get()
                let client = clients.removeFirst()
                nextClients.set(clients)
                return client
            },
            autoReconnectCoordinator: coordinator
        )

        state.connect(settings: makeSettings())
        await state.acknowledgeAgreementWhenReady()
        await state.waitForSettling()

        guard case .connected = state.phase else {
            Issue.record("expected .connected after initial connect, got \(String(describing: state.phase))")
            return
        }

        // Server-side drop without "server error" prefix → policy should retry.
        firstFake.simulateDisconnect(reason: "Connection reset by peer")

        // Wait briefly for the watcher to run.
        try? await Task.sleep(for: .milliseconds(30))

        // Phase should be .connecting, not .failed; counter at 1.
        if case .connecting = state.phase {
            #expect(coordinator.attempt == 1)
        } else {
            Issue.record("expected .connecting (auto-reconnect), got \(String(describing: state.phase))")
        }
    }

    @Test("successful reconnect resets the counter")
    func successfulReconnectResetsCounter() async {
        let scratch = Scratch()
        defer { scratch.teardown() }
        scratch.defaults.set(true, forKey: AppStorageKeys.autoReconnectEnabled)
        scratch.defaults.set(3, forKey: AppStorageKeys.autoReconnectMaxAttempts)
        scratch.defaults.set(0, forKey: AppStorageKeys.autoReconnectDelaySeconds)

        let firstFake = FakeHotlineClient()
        let secondFake = FakeHotlineClient()
        let nextClients = Mutex<[FakeHotlineClient]>([firstFake, secondFake])
        let coordinator = makeCoordinator(defaults: scratch.defaults)
        let state = makeTestHostState(
            connector: { _, _, _ in
                var clients = nextClients.get()
                let client = clients.removeFirst()
                nextClients.set(clients)
                return client
            },
            autoReconnectCoordinator: coordinator
        )

        state.connect(settings: makeSettings())
        await state.acknowledgeAgreementWhenReady()
        await state.waitForSettling()

        firstFake.simulateDisconnect(reason: "Connection reset by peer")

        // Give the disconnect watcher a tick to flip phase to .connecting
        // (the helpers below only loop while phase == .connecting; if we
        // run them before the watcher fires, they return immediately and
        // the assertion below would pass for the wrong reason).
        try? await Task.sleep(for: .milliseconds(30))

        // Let the coordinator schedule + the connect Task race to
        // .connected on the second fake.
        await state.acknowledgeAgreementWhenReady()
        await state.waitForSettling()

        if case .connected = state.phase {
            #expect(coordinator.attempt == 0)
        } else {
            Issue.record("expected .connected after auto-reconnect, got \(String(describing: state.phase))")
        }
    }

    @Test("disconnect() cancels the coordinator")
    func userDisconnectCancelsCoordinator() async {
        let scratch = Scratch()
        defer { scratch.teardown() }
        scratch.defaults.set(true, forKey: AppStorageKeys.autoReconnectEnabled)
        scratch.defaults.set(3, forKey: AppStorageKeys.autoReconnectMaxAttempts)
        // Long enough delay that the user's disconnect lands before the retry.
        scratch.defaults.set(60, forKey: AppStorageKeys.autoReconnectDelaySeconds)

        let firstFake = FakeHotlineClient()
        // Use a real sleep here so the 60-s configured delay actually
        // leaves the retry parked while the user calls Disconnect.
        let coordinator = makeCoordinator(
            defaults: scratch.defaults,
            sleep: { duration in try? await Task.sleep(for: duration) }
        )
        let connectorCalls = Mutex(0)
        let state = makeTestHostState(
            connector: { _, _, _ in
                connectorCalls.set(connectorCalls.get() + 1)
                return firstFake
            },
            autoReconnectCoordinator: coordinator
        )

        state.connect(settings: makeSettings())
        await state.acknowledgeAgreementWhenReady()
        await state.waitForSettling()
        #expect(connectorCalls.get() == 1)

        firstFake.simulateDisconnect(reason: "Connection reset by peer")
        try? await Task.sleep(for: .milliseconds(30))

        // We're now in the inter-attempt sleep. disconnect() should
        // stop further attempts.
        state.disconnect()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(connectorCalls.get() == 1)
        if case .disconnected = state.phase { } else {
            Issue.record("expected .disconnected after user disconnect, got \(String(describing: state.phase))")
        }
    }

    @Test("manual retry resets the counter")
    func manualRetryResetsCounter() async {
        let scratch = Scratch()
        defer { scratch.teardown() }
        scratch.defaults.set(true, forKey: AppStorageKeys.autoReconnectEnabled)
        scratch.defaults.set(3, forKey: AppStorageKeys.autoReconnectMaxAttempts)
        scratch.defaults.set(0, forKey: AppStorageKeys.autoReconnectDelaySeconds)

        // Connector that always throws — coordinator burns all attempts,
        // then we manually retry.
        struct Boom: Error {}
        let coordinator = makeCoordinator(defaults: scratch.defaults)
        let state = makeTestHostState(
            connector: { _, _, _ in throw Boom() },
            autoReconnectCoordinator: coordinator
        )

        state.connect(settings: makeSettings("Carpe"))
        await state.waitForSettling()
        // Initial attempt failed; coordinator hasn't kicked in (no live
        // session ever existed). Pre-populate counter to simulate a
        // post-cycle state.
        coordinator.scheduleRetry { }
        coordinator.scheduleRetry { }
        try? await Task.sleep(for: .milliseconds(30))
        #expect(coordinator.attempt == 2)

        state.retry()
        #expect(coordinator.attempt == 0)
    }

    @Test("manual retry forwards the saved keychain password to connect")
    func manualRetryReadsKeychain() async {
        let scratch = Scratch()
        defer { scratch.teardown() }
        scratch.defaults.set(true, forKey: AppStorageKeys.autoReconnectEnabled)
        scratch.defaults.set(3, forKey: AppStorageKeys.autoReconnectMaxAttempts)
        scratch.defaults.set(0, forKey: AppStorageKeys.autoReconnectDelaySeconds)

        // Unique address so the keychain entry + session cache can't collide
        // with any other suite that seeds "sample.example.com".
        let settings = ConnectionSettings(
            name: "Test",
            address: "manual-retry-\(UUID().uuidString).example.com",
            port: 5500,
            nickname: "tester"
        )
        let key = KeychainPasswordStore.Key.canonical(
            address: settings.address,
            port: settings.port,
            login: settings.login
        )
        try? KeychainPasswordStore.save("seekrit", for: key)
        defer { try? KeychainPasswordStore.delete(for: key) }

        // Always-throwing connector: we only care which password reaches it.
        struct Boom: Error {}
        let passwordsSeen = Mutex<[String]>([])
        let coordinator = makeCoordinator(defaults: scratch.defaults)
        let state = makeTestHostState(
            connector: { _, password, _ in
                passwordsSeen.set(passwordsSeen.get() + [password])
                throw Boom()
            },
            autoReconnectCoordinator: coordinator
        )

        // First connect carries no password (mirrors a fresh menu Connect
        // where the user relied on the saved credential): connector sees "".
        state.connect(settings: settings)
        await state.waitForSettling()

        // User-initiated retry must look the password back out of the keychain.
        state.retry()
        await state.waitForSettling()

        #expect(passwordsSeen.get() == ["", "seekrit"])
    }

    @Test("coordinator-initiated retry forwards the saved password to connect")
    func retryWithSavedPasswordReadsKeychain() async {
        let scratch = Scratch()
        defer { scratch.teardown() }
        scratch.defaults.set(true, forKey: AppStorageKeys.autoReconnectEnabled)
        scratch.defaults.set(3, forKey: AppStorageKeys.autoReconnectMaxAttempts)
        scratch.defaults.set(0, forKey: AppStorageKeys.autoReconnectDelaySeconds)

        let settings = makeSettings()
        // Seed the keychain with a known password for this triple. Clean
        // up after the test so other test runs aren't perturbed.
        let key = KeychainPasswordStore.Key.canonical(
            address: settings.address,
            port: settings.port,
            login: settings.login
        )
        try? KeychainPasswordStore.save("seekrit", for: key)
        defer { try? KeychainPasswordStore.delete(for: key) }

        let firstFake = FakeHotlineClient()
        let secondFake = FakeHotlineClient()
        let nextClients = Mutex<[FakeHotlineClient]>([firstFake, secondFake])
        let coordinator = makeCoordinator(defaults: scratch.defaults)
        // Capture the password actually passed to the connector on each call.
        let passwordsSeen = Mutex<[String]>([])
        let state = makeTestHostState(
            connector: { _, password, _ in
                passwordsSeen.set(passwordsSeen.get() + [password])
                var clients = nextClients.get()
                let client = clients.removeFirst()
                nextClients.set(clients)
                return client
            },
            autoReconnectCoordinator: coordinator
        )

        state.connect(settings: settings, password: "seekrit", rememberPassword: true)
        await state.acknowledgeAgreementWhenReady()
        await state.waitForSettling()

        firstFake.simulateDisconnect(reason: "Connection reset by peer")
        // Give the disconnect watcher a chance to flip phase to .connecting
        // and schedule the retry — mirrors the pattern in
        // `unexpectedDisconnectTriggersReconnect` above. Without this the
        // helper polls observe phase still as `.connected` from the prior
        // fake and exit before the second connector call happens.
        try? await Task.sleep(for: .milliseconds(30))
        await state.acknowledgeAgreementWhenReady()
        await state.waitForSettling()

        #expect(passwordsSeen.get() == ["seekrit", "seekrit"])
    }

    @Test("auth-failure during reconnect stops the cycle")
    func authFailureDuringReconnectStopsCycle() async {
        let scratch = Scratch()
        defer { scratch.teardown() }
        scratch.defaults.set(true, forKey: AppStorageKeys.autoReconnectEnabled)
        scratch.defaults.set(3, forKey: AppStorageKeys.autoReconnectMaxAttempts)
        scratch.defaults.set(0, forKey: AppStorageKeys.autoReconnectDelaySeconds)

        // First call → succeed. Subsequent calls → throw a serverError
        // (the protocol's auth-rejection shape).
        let firstFake = FakeHotlineClient()
        let connectorCalls = Mutex(0)
        let coordinator = makeCoordinator(defaults: scratch.defaults)
        let state = makeTestHostState(
            connector: { _, _, _ in
                let count = connectorCalls.get()
                connectorCalls.set(count + 1)
                if count == 0 { return firstFake }
                throw HotlineError.serverError(id: 1, message: "bad password")
            },
            autoReconnectCoordinator: coordinator
        )

        state.connect(settings: makeSettings())
        await state.acknowledgeAgreementWhenReady()
        await state.waitForSettling()

        firstFake.simulateDisconnect(reason: "Connection reset by peer")
        // Give the disconnect watcher time to fire, the coordinator to
        // schedule + execute the retry, and the retry's connector throw
        // to land in the catch block.
        try? await Task.sleep(for: .milliseconds(80))

        // Exactly 2 connector calls: initial connect + one failed retry.
        #expect(connectorCalls.get() == 2)
        if case .failed = state.phase { } else {
            Issue.record("expected .failed after auth-fail, got \(String(describing: state.phase))")
        }
    }

    @Test("hitting max attempts ends in .failed; counter does not exceed max")
    func maxAttemptsLandsFailed() async {
        let scratch = Scratch()
        defer { scratch.teardown() }
        scratch.defaults.set(true, forKey: AppStorageKeys.autoReconnectEnabled)
        scratch.defaults.set(3, forKey: AppStorageKeys.autoReconnectMaxAttempts)
        scratch.defaults.set(0, forKey: AppStorageKeys.autoReconnectDelaySeconds)

        struct Transport: Error {}
        let firstFake = FakeHotlineClient()
        let connectorCalls = Mutex(0)
        let coordinator = makeCoordinator(defaults: scratch.defaults)
        let state = makeTestHostState(
            connector: { _, _, _ in
                let count = connectorCalls.get()
                connectorCalls.set(count + 1)
                if count == 0 { return firstFake }
                throw Transport()  // not a HotlineError.serverError → keep retrying
            },
            autoReconnectCoordinator: coordinator
        )

        state.connect(settings: makeSettings())
        await state.acknowledgeAgreementWhenReady()
        await state.waitForSettling()

        firstFake.simulateDisconnect(reason: "Connection reset by peer")
        // Wait long enough for all retries to fire (delay 0 + scheduling).
        try? await Task.sleep(for: .milliseconds(250))

        // Initial connect + 3 reconnect attempts = 4 connector calls.
        #expect(connectorCalls.get() == 4)
        #expect(coordinator.attempt == 3)
        if case .failed = state.phase { } else {
            Issue.record("expected .failed after exhausting attempts, got \(String(describing: state.phase))")
        }
    }

    @Test("kick (reason contains 'server error') skips auto-reconnect")
    func kickFilterSkipsRetry() async {
        let scratch = Scratch()
        defer { scratch.teardown() }
        scratch.defaults.set(true, forKey: AppStorageKeys.autoReconnectEnabled)
        scratch.defaults.set(3, forKey: AppStorageKeys.autoReconnectMaxAttempts)
        scratch.defaults.set(0, forKey: AppStorageKeys.autoReconnectDelaySeconds)

        let firstFake = FakeHotlineClient()
        let connectorCalls = Mutex(0)
        let coordinator = makeCoordinator(defaults: scratch.defaults)
        let state = makeTestHostState(
            connector: { _, _, _ in
                connectorCalls.set(connectorCalls.get() + 1)
                return firstFake
            },
            autoReconnectCoordinator: coordinator
        )

        state.connect(settings: makeSettings())
        await state.acknowledgeAgreementWhenReady()
        await state.waitForSettling()

        firstFake.simulateDisconnect(reason: "server error 5: kicked by admin")
        try? await Task.sleep(for: .milliseconds(50))

        // No reconnect attempt — only the initial connect ran.
        #expect(connectorCalls.get() == 1)
        if case .failed = state.phase { } else {
            Issue.record("expected .failed (kick), got \(String(describing: state.phase))")
        }
        #expect(coordinator.attempt == 0)
    }
}
