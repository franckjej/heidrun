import Foundation
import Testing
@testable import Heidrun
import CommonTools
import HeidrunCore

@MainActor
@Suite("HostState")
struct HostStateTests {
    private func makeSettings(_ name: String = "Test") -> ConnectionSettings {
        ConnectionSettings(name: name, address: "127.0.0.1", port: 5500, nickname: "tester")
    }

    @Test("connect records lastAttemptedSettings immediately")
    func connectRecordsAttempt() {
        let state = makeTestHostState()
        let settings = makeSettings()
        state.connect(settings: settings)
        #expect(state.lastAttemptedSettings == settings)
    }

    @Test("lastAttemptedSettings is nil before any connect")
    func initiallyNil() {
        let state = makeTestHostState()
        #expect(state.lastAttemptedSettings == nil)
    }

    @Test("serverName returns em-dash when no attempt yet")
    func serverNameDefault() {
        let state = makeTestHostState()
        #expect(state.serverName == "—")
    }

    @Test("serverName uses settings name when present")
    func serverNameFromName() {
        let state = makeTestHostState()
        state.lastAttemptedSettings = ConnectionSettings(name: "Carpe Diem", address: "hl.example.com")
        #expect(state.serverName == "Carpe Diem")
    }

    @Test("serverName falls back to address when name is empty")
    func serverNameFallbackToAddress() {
        let state = makeTestHostState()
        state.lastAttemptedSettings = ConnectionSettings(name: "", address: "hl.example.com")
        #expect(state.serverName == "hl.example.com")
    }

    @Test("connect uses the injected connector and transitions to .connected")
    func connectUsesInjectedConnector() async {
        let fake = FakeHotlineClient()
        let state = makeTestHostState(connector: { _, _, _ in fake })
        state.connect(settings: makeSettings())
        // The connect Task awaits the agreement sheet after login.
        // Short-circuit it so the test doesn't have to sit through the
        // 2-second no-agreement timeout. Poll briefly so the call lands
        // after the connect Task has installed the agreement continuation.
        await state.acknowledgeAgreementWhenReady()
        await state.waitForSettling()
        if case .connected(let client) = state.phase {
            #expect(client as? FakeHotlineClient === fake)
        } else {
            Issue.record("expected .connected, got \(String(describing: state.phase))")
        }
    }

    @Test("connector failure transitions to .failed")
    func connectorFailureTransitionsToFailed() async {
        struct Boom: Error {}
        let state = makeTestHostState(connector: { _, _, _ in throw Boom() })
        state.connect(settings: makeSettings())
        await state.waitForSettling()
        if case .failed = state.phase { } else {
            Issue.record("expected .failed, got \(String(describing: state.phase))")
        }
    }

    @Test("cancelConnect during connecting returns to disconnected and cancels task")
    func cancelConnectDuringConnecting() async {
        // Connector that hangs until cancelled; lets us observe Task.isCancelled.
        let sawCancellation = Mutex(false)
        let state = makeTestHostState(connector: { _, _, _ in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(5))
            }
            sawCancellation.set(true)
            throw CancellationError()
        })
        state.connect(settings: makeSettings())
        // Give the connector one tick to start.
        try? await Task.sleep(for: .milliseconds(20))
        #expect({ if case .connecting = state.phase { true } else { false } }())

        state.cancelConnect()
        #expect({ if case .disconnected = state.phase { true } else { false } }())

        // Let the task observe cancellation.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(sawCancellation.get() == true)
    }

    @Test("cancelConnect is a no-op outside .connecting")
    func cancelConnectIsNoOpOutsideConnecting() {
        let state = makeTestHostState()
        state.cancelConnect()
        #expect({ if case .disconnected = state.phase { true } else { false } }())
    }

    @Test("retry after failure resubmits the last settings")
    func retryAfterFailure() async {
        struct Boom: Error {}
        let attempts = Mutex(0)
        let state = makeTestHostState(connector: { _, _, _ in
            attempts.set(attempts.get() + 1)
            throw Boom()
        })
        state.connect(settings: makeSettings("Carpe"))
        await state.waitForSettling()
        #expect({ if case .failed = state.phase { true } else { false } }())
        #expect(attempts.get() == 1)

        state.retry()
        await state.waitForSettling()
        #expect(attempts.get() == 2)
        #expect(state.lastAttemptedSettings?.name == "Carpe")
    }

    @Test("retry is no-op when nothing was attempted")
    func retryNoOpWithoutHistory() {
        let state = makeTestHostState()
        state.retry()
        #expect({ if case .disconnected = state.phase { true } else { false } }())
    }

    @Test("requestPartialResume populates lastAttemptedSettings and pendingPostConnectResume")
    func requestPartialResumePopulatesState() async {
        let fake = FakeHotlineClient()
        let state = makeTestHostState(connector: { _, _, _ in fake })

        let metadata = PartialDownloadMetadata(
            serverAddress: "h.example.org",
            serverPort: 5500,
            serverLogin: "guest",
            serverName: "Example",
            remotePath: ["pub"],
            remoteFileName: "foo.dmg",
            totalSize: 1024
        )
        let request = PartialResumeRequest(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/foo.dmg.heidrunpart"),
            metadata: metadata,
            bytesOnDisk: 256
        )

        state.requestPartialResume(request)

        #expect(state.lastAttemptedSettings?.address == "h.example.org")
        #expect(state.lastAttemptedSettings?.port == 5500)
        #expect(state.lastAttemptedSettings?.login == "guest")
        #expect(state.lastAttemptedSettings?.name == "Example")
        // The connect Task hasn't run far enough to consume the pending
        // resume yet — it's parked at the agreement gate. So the property
        // is still populated here.
        #expect(state.pendingPostConnectResume?.id == request.id)
        if case .connecting = state.phase { } else {
            Issue.record("expected .connecting after requestPartialResume, got \(String(describing: state.phase))")
        }

        // Cancel so the test doesn't leave the connect Task spinning on
        // the 2-second no-agreement timeout.
        state.cancelConnect()
    }

    @Test("partialResumeSettings reads the saved nickname so login fires")
    func partialResumeSettingsPreservesLoginNickname() {
        // Use an isolated, scratch UserDefaults so we don't perturb the
        // user's real preferences (or fight other tests that touch the
        // same keys).
        let defaults = UserDefaults(suiteName: "HostStateTests.partialResumeSettings")!
        defaults.removePersistentDomain(forName: "HostStateTests.partialResumeSettings")
        defer { defaults.removePersistentDomain(forName: "HostStateTests.partialResumeSettings") }

        defaults.set("tester", forKey: AppStorageKeys.defaultNickname)
        defaults.set(42, forKey: AppStorageKeys.defaultIconID)

        let request = PartialResumeRequest(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/foo.dmg.heidrunpart"),
            metadata: PartialDownloadMetadata(
                serverAddress: "h.example.org",
                serverPort: 5500,
                serverLogin: "guest",
                serverName: "Example",
                remotePath: ["pub"],
                remoteFileName: "foo.dmg",
                totalSize: 1024
            ),
            bytesOnDisk: 256
        )

        let settings = HostState.partialResumeSettings(for: request, defaults: defaults)

        // The regression: nickname must be non-empty so `HostState.connect`
        // actually puts the login transaction on the wire.
        #expect(!settings.nickname.isEmpty)
        #expect(settings.nickname == "tester")
        #expect(settings.icon == 42)
        #expect(settings.login == "guest")
        #expect(settings.address == "h.example.org")
        #expect(settings.port == 5500)
        #expect(settings.name == "Example")
    }

    @Test("partialResumeSettings falls back to NSFullUserName when the default is unset")
    func partialResumeSettingsFallsBackToFullUserName() {
        let defaults = UserDefaults(suiteName: "HostStateTests.partialResumeFallback")!
        defaults.removePersistentDomain(forName: "HostStateTests.partialResumeFallback")
        defer { defaults.removePersistentDomain(forName: "HostStateTests.partialResumeFallback") }

        let request = PartialResumeRequest(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/foo.dmg.heidrunpart"),
            metadata: PartialDownloadMetadata(
                serverAddress: "h.example.org",
                serverPort: 5500,
                serverLogin: "guest",
                serverName: "Example",
                remotePath: ["pub"],
                remoteFileName: "foo.dmg",
                totalSize: 1024
            ),
            bytesOnDisk: 0
        )

        let settings = HostState.partialResumeSettings(for: request, defaults: defaults)

        // With no stored nickname we use `NSFullUserName()` — also non-empty
        // on any real Mac, so the login still goes out.
        #expect(!settings.nickname.isEmpty)
        #expect(settings.nickname == NSFullUserName())
        #expect(settings.icon == 0)
    }

    @Test("requestPartialResume reuses the live connection when the server matches")
    func requestPartialResumeReusesMatchingConnection() async {
        let fake = FakeHotlineClient()
        let state = makeTestHostState(connector: { _, _, _ in fake })
        // Get into .connected against 127.0.0.1:5500 (matches makeSettings()).
        state.connect(settings: makeSettings())
        await state.acknowledgeAgreementWhenReady()
        await state.waitForSettling()
        guard case .connected = state.phase else {
            Issue.record("expected .connected before reuse path; got \(String(describing: state.phase))")
            return
        }

        let request = PartialResumeRequest(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/foo.dmg.heidrunpart"),
            metadata: PartialDownloadMetadata(
                serverAddress: "127.0.0.1",
                serverPort: 5500,
                serverLogin: "guest",
                serverName: "Test",
                remotePath: ["pub"],
                remoteFileName: "foo.dmg",
                totalSize: 1024
            ),
            bytesOnDisk: 256
        )
        state.requestPartialResume(request)

        // Stays connected: no fresh connect Task started, no disconnect.
        if case .connected = state.phase { } else {
            Issue.record("expected .connected after reuse path; got \(String(describing: state.phase))")
        }
        #expect(state.pendingPostConnectResume == nil)
        #expect(fake.didDisconnect == false)
    }

    @Test("requestPartialResume reconnects when the server differs from the live one")
    func requestPartialResumeReconnectsOnMismatch() async {
        let fake = FakeHotlineClient()
        let state = makeTestHostState(connector: { _, _, _ in fake })
        state.connect(settings: makeSettings())
        await state.acknowledgeAgreementWhenReady()
        await state.waitForSettling()
        guard case .connected = state.phase else {
            Issue.record("expected .connected before mismatch path; got \(String(describing: state.phase))")
            return
        }

        let request = PartialResumeRequest(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/foo.dmg.heidrunpart"),
            metadata: PartialDownloadMetadata(
                serverAddress: "other.example.org",     // different address
                serverPort: 5500,
                serverLogin: "guest",
                serverName: "Other",
                remotePath: ["pub"],
                remoteFileName: "foo.dmg",
                totalSize: 1024
            ),
            bytesOnDisk: 256
        )
        state.requestPartialResume(request)

        // Mismatch → tear down the live connection and start a fresh
        // connect Task. We park here at .connecting (the connect Task is
        // waiting for the agreement gate).
        #expect(state.pendingPostConnectResume?.id == request.id)
        #expect(state.lastAttemptedSettings?.address == "other.example.org")

        state.cancelConnect()
    }

    @Test("requestPartialResume clears prior pending resume and unreadable sheets")
    func requestPartialResumeClearsStaleSheets() {
        let fake = FakeHotlineClient()
        let state = makeTestHostState(connector: { _, _, _ in fake })

        let staleResume = PartialResumeRequest(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/stale.dmg.heidrunpart"),
            metadata: PartialDownloadMetadata(
                serverAddress: "old.example.org",
                serverPort: 5500,
                serverLogin: "guest",
                serverName: "Old",
                remotePath: ["pub"],
                remoteFileName: "stale.dmg",
                totalSize: 1024
            ),
            bytesOnDisk: 128
        )
        let staleUnreadable = PartialDownloadUnreadable(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/stale.dmg.heidrunpart"),
            reason: "stale"
        )
        state.pendingResume = staleResume
        state.pendingUnreadablePartial = staleUnreadable

        let request = PartialResumeRequest(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/foo.dmg.heidrunpart"),
            metadata: PartialDownloadMetadata(
                serverAddress: "h.example.org",
                serverPort: 5500,
                serverLogin: "guest",
                serverName: "Example",
                remotePath: ["pub"],
                remoteFileName: "foo.dmg",
                totalSize: 1024
            ),
            bytesOnDisk: 256
        )
        state.requestPartialResume(request)

        #expect(state.pendingResume == nil)
        #expect(state.pendingUnreadablePartial == nil)

        // Tear down so the connect Task doesn't outlive the test.
        state.cancelConnect()
    }

    @Test("cancelConnect clears pendingPostConnectResume so it doesn't leak across reconnects")
    func cancelConnectClearsPendingPostConnectResume() async {
        let sawCancellation = Mutex(false)
        let state = makeTestHostState(connector: { _, _, _ in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(5))
            }
            sawCancellation.set(true)
            throw CancellationError()
        })

        let request = PartialResumeRequest(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/foo.dmg.heidrunpart"),
            metadata: PartialDownloadMetadata(
                serverAddress: "h.example.org",
                serverPort: 5500,
                serverLogin: "guest",
                serverName: "Example",
                remotePath: ["pub"],
                remoteFileName: "foo.dmg",
                totalSize: 1024
            ),
            bytesOnDisk: 256
        )
        state.requestPartialResume(request)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(state.pendingPostConnectResume?.id == request.id)

        state.cancelConnect()
        #expect(state.pendingPostConnectResume == nil)

        try? await Task.sleep(for: .milliseconds(50))
        #expect(sawCancellation.get() == true)
    }

    @Test("connector failure clears pendingPostConnectResume so reconnects don't fire the stale hook")
    func connectorFailureClearsPendingPostConnectResume() async {
        struct Boom: Error {}
        let state = makeTestHostState(connector: { _, _, _ in throw Boom() })

        let request = PartialResumeRequest(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/foo.dmg.heidrunpart"),
            metadata: PartialDownloadMetadata(
                serverAddress: "h.example.org",
                serverPort: 5500,
                serverLogin: "guest",
                serverName: "Example",
                remotePath: ["pub"],
                remoteFileName: "foo.dmg",
                totalSize: 1024
            ),
            bytesOnDisk: 256
        )
        state.requestPartialResume(request)
        await state.waitForSettling()

        #expect({ if case .failed = state.phase { true } else { false } }())
        #expect(state.pendingPostConnectResume == nil)
    }

    @Test("retry from .disconnected after dismiss resubmits the last attempt")
    func retryFromDisconnectedAfterDismiss() async {
        struct Boom: Error {}
        let attempts = Mutex(0)
        let state = makeTestHostState(connector: { _, _, _ in
            attempts.set(attempts.get() + 1)
            throw Boom()
        })
        state.connect(settings: makeSettings("Carpe"))
        await state.waitForSettling()
        #expect({ if case .failed = state.phase { true } else { false } }())

        // Simulate the FailedBanner's Dismiss action.
        state.phase = .disconnected
        #expect(state.lastAttemptedSettings?.name == "Carpe")

        state.retry()
        await state.waitForSettling()
        #expect(attempts.get() == 2)
    }

    @Test("connect saves the password to the keychain when rememberPassword is true and connect succeeds")
    func connectSavesPasswordWhenRememberOn() async throws {
        let key = KeychainPasswordStore.Key.canonical(
            address: "kctest-\(UUID().uuidString).example",
            port: 5500,
            login: "tester"
        )
        defer { try? KeychainPasswordStore.delete(for: key) }

        let fake = FakeHotlineClient()
        let state = makeTestHostState(connector: { _, _, _ in fake })
        let settings = ConnectionSettings(
            name: "Test",
            address: key.address,
            port: key.port,
            nickname: "tester",
            login: key.login
        )

        state.connect(settings: settings, password: "hunter2", rememberPassword: true)
        await state.acknowledgeAgreementWhenReady()
        await state.waitForSettling()

        guard case .connected = state.phase else {
            Issue.record("expected .connected, got \(String(describing: state.phase))")
            return
        }
        #expect(try KeychainPasswordStore.read(for: key) == "hunter2")
    }

    @Test("connect deletes the saved password when rememberPassword is false")
    func connectDeletesPasswordWhenRememberOff() async throws {
        let key = KeychainPasswordStore.Key.canonical(
            address: "kctest-\(UUID().uuidString).example",
            port: 5500,
            login: "tester"
        )
        defer { try? KeychainPasswordStore.delete(for: key) }

        // Seed a saved password the user is about to clear.
        try KeychainPasswordStore.save("oldsecret", for: key)

        let fake = FakeHotlineClient()
        let state = makeTestHostState(connector: { _, _, _ in fake })
        let settings = ConnectionSettings(
            name: "Test",
            address: key.address,
            port: key.port,
            nickname: "tester",
            login: key.login
        )

        state.connect(settings: settings, password: "ignored", rememberPassword: false)
        await state.acknowledgeAgreementWhenReady()
        await state.waitForSettling()

        guard case .connected = state.phase else {
            Issue.record("expected .connected, got \(String(describing: state.phase))")
            return
        }
        #expect(try KeychainPasswordStore.read(for: key) == nil)
    }

    @Test("connect does not save the password on failure")
    func connectDoesNotSaveOnFailure() async throws {
        struct Boom: Error {}
        let key = KeychainPasswordStore.Key.canonical(
            address: "kctest-\(UUID().uuidString).example",
            port: 5500,
            login: "tester"
        )
        defer { try? KeychainPasswordStore.delete(for: key) }

        let state = makeTestHostState(connector: { _, _, _ in throw Boom() })
        let settings = ConnectionSettings(
            name: "Test",
            address: key.address,
            port: key.port,
            nickname: "tester",
            login: key.login
        )

        state.connect(settings: settings, password: "hunter2", rememberPassword: true)
        await state.waitForSettling()

        guard case .failed = state.phase else {
            Issue.record("expected .failed, got \(String(describing: state.phase))")
            return
        }
        #expect(try KeychainPasswordStore.read(for: key) == nil)
    }

    @Test("a second connect's rememberPassword overrides the first attempt's policy")
    func backToBackConnectAppliesSecondPolicy() async throws {
        let key = KeychainPasswordStore.Key.canonical(
            address: "kctest-\(UUID().uuidString).example",
            port: 5500,
            login: "tester"
        )
        defer { try? KeychainPasswordStore.delete(for: key) }

        let fake = FakeHotlineClient()
        let state = makeTestHostState(connector: { _, _, _ in fake })
        let settings = ConnectionSettings(
            name: "Test",
            address: key.address,
            port: key.port,
            nickname: "tester",
            login: key.login
        )

        // First attempt: would save "first" if it ran to completion.
        state.connect(settings: settings, password: "first", rememberPassword: true)
        // Second attempt fires before the first settles. The second's
        // (password: "second", remember: true) policy is what must land.
        state.connect(settings: settings, password: "second", rememberPassword: true)
        await state.acknowledgeAgreementWhenReady()
        await state.waitForSettling()

        guard case .connected = state.phase else {
            Issue.record("expected .connected, got \(String(describing: state.phase))")
            return
        }
        #expect(try KeychainPasswordStore.read(for: key) == "second")
    }

    @Test("requestPartialResume passes the keychain-saved password into login")
    func requestPartialResumePullsSavedPassword() async throws {
        let key = KeychainPasswordStore.Key.canonical(
            address: "kctest-\(UUID().uuidString).example",
            port: 5500,
            login: "tester"
        )
        defer { try? KeychainPasswordStore.delete(for: key) }
        try KeychainPasswordStore.save("hunter2", for: key)

        let fake = FakeHotlineClient()
        let state = makeTestHostState(connector: { _, _, _ in fake })

        let request = PartialResumeRequest(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/x.heidrunpart"),
            metadata: PartialDownloadMetadata(
                serverAddress: key.address,
                serverPort: key.port,
                serverLogin: key.login,
                serverName: "Example",
                remotePath: ["pub"],
                remoteFileName: "x.bin",
                totalSize: 1024
            ),
            bytesOnDisk: 0
        )
        state.requestPartialResume(request)
        await state.acknowledgeAgreementWhenReady()
        await state.waitForSettling()

        guard case .connected = state.phase else {
            Issue.record("expected .connected, got \(String(describing: state.phase))")
            return
        }
        #expect(fake.lastLogin?.password == "hunter2")
    }

    @Test("requestPartialResume with no saved password sends an empty login password and does not save")
    func requestPartialResumeWithNoSavedPasswordPassesEmpty() async throws {
        let key = KeychainPasswordStore.Key.canonical(
            address: "kctest-\(UUID().uuidString).example",
            port: 5500,
            login: "tester"
        )
        defer { try? KeychainPasswordStore.delete(for: key) }
        // Intentionally do NOT seed the keychain.

        let fake = FakeHotlineClient()
        let state = makeTestHostState(connector: { _, _, _ in fake })

        let request = PartialResumeRequest(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/x.heidrunpart"),
            metadata: PartialDownloadMetadata(
                serverAddress: key.address,
                serverPort: key.port,
                serverLogin: key.login,
                serverName: "Example",
                remotePath: ["pub"],
                remoteFileName: "x.bin",
                totalSize: 1024
            ),
            bytesOnDisk: 0
        )
        state.requestPartialResume(request)
        await state.acknowledgeAgreementWhenReady()
        await state.waitForSettling()

        guard case .connected = state.phase else {
            Issue.record("expected .connected, got \(String(describing: state.phase))")
            return
        }
        // No saved entry → empty password reaches login.
        #expect(fake.lastLogin?.password.isEmpty == true)
        // rememberPassword:true + empty password must NOT have re-created
        // a keychain entry. Guards the empty-password short-circuit in
        // applyKeychainPolicyAfterConnect.
        #expect(try KeychainPasswordStore.read(for: key) == nil)
    }
}
