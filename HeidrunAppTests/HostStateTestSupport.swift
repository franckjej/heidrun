import Foundation
@testable import Heidrun
import HeidrunCore

// MARK: - FakeHotlineClient

/// Shared `HotlineClient` test double used by every `HostState`-touching
/// suite. Uses `EventBroadcaster` (the same machinery production
/// `HotlineNetworkClient` uses) so each `client.events` access — and
/// `HostState` subscribes twice, once from `startWatchingAgreement` and
/// once from `startWatchingDisconnect` — gets its own AsyncStream. A
/// single shared `AsyncStream` would race because it is single-consumer.
///
/// Captures the most recent `login(...)` call so credential-flow tests
/// can assert on the password argument. `simulateDisconnect(reason:)`
/// yields a `.disconnected` event and finishes the broadcaster — used
/// by tests that exercise the auto-reconnect cycle.
final class FakeHotlineClient: HotlineClient, @unchecked Sendable {
    private let broadcaster = EventBroadcaster()
    private(set) var didDisconnect = false

    struct LoginCall: Sendable, Equatable {
        let name: String
        let password: String
        let nickname: String
        let icon: UInt16
    }
    private(set) var lastLogin: LoginCall?

    nonisolated var events: AsyncStream<HotlineEvent> {
        broadcaster.makeStream()
    }

    var connectionInfo: HotlineConnectionInfo {
        get async {
            HotlineConnectionInfo(
                clientVersion: 0,
                protocolVersion: 0,
                connectionSocket: 0,
                lastTaskNumber: 0,
                settings: ConnectionSettings(name: "", address: "127.0.0.1")
            )
        }
    }

    init() {}

    /// Yield a `.disconnected` event and end the event stream. Used by
    /// tests that need the disconnect watcher to fire — e.g. all the
    /// auto-reconnect cycle tests in `HostStateAutoReconnectTests`.
    func simulateDisconnect(reason: String?) {
        broadcaster.yield(.disconnected(reason: reason))
        broadcaster.finish()
    }

    func disconnect() async { didDisconnect = true; broadcaster.finish() }
    func requestAttention(_ flags: AttentionFlags) async {}
    func sendPing() async throws {}
    func login(name: String, password: String, nickname: String, icon: UInt16, emoji: String?) async throws {
        lastLogin = LoginCall(name: name, password: password, nickname: nickname, icon: icon)
    }
    func agreeToAgreement(nickname: String, icon: UInt16, emoji: String?) async throws {}
    func changeNickname(_ nickname: String, icon: UInt16, emoji: String?, persist: Bool) async throws {}
    func fetchUserList() async throws -> [User] { [] }
    func fetchUserInfo(socket: UInt16) async throws -> UserInfo {
        UserInfo(user: User(socket: socket), infoText: "")
    }
    func kick(socket: UInt16, ban: Bool) async throws {}
    func fetchNewsFeed() async throws -> String { "" }
    func postPlainNews(_ text: String) async throws {}
    func broadcast(_ message: String) async throws {}
    func sendPrivateMessage(_ message: String, to socket: UInt16) async throws {}
    func sendChat(_ message: String, in chat: ChatID?, isAction: Bool) async throws {}
    func createPrivateChat(with socket: UInt16) async throws -> ChatID { ChatID(rawValue: 0) }
    func joinPrivateChat(_ chat: ChatID) async throws {}
    func rejectPrivateChat(_ chat: ChatID) async throws {}
    func leavePrivateChat(_ chat: ChatID) async throws {}
    func changeChatSubject(_ subject: String, in chat: ChatID) async throws {}
    func invite(socket: UInt16, to chat: ChatID) async throws {}
    func createLogin(name: String, password: String, nickname: String, privileges: UserPrivileges) async throws {}
    func deleteLogin(_ name: String) async throws {}
    func openLogin(_ name: String) async throws -> (nickname: String, privileges: UserPrivileges) {
        (nickname: "", privileges: [])
    }
    func modifyLogin(name: String, password: String?, nickname: String, privileges: UserPrivileges) async throws {}
    func fetchNewsBundles(at path: RemotePath) async throws -> [NewsBundle] { [] }
    func fetchNewsThreads(at path: RemotePath) async throws -> [NewsThread] { [] }
    func fetchNewsThread(at path: RemotePath, threadID: UInt16, type: String) async throws -> NewsThread {
        NewsThread(threadID: threadID)
    }
    func deleteNewsBundle(at path: RemotePath) async throws {}
    func deleteNewsThread(at path: RemotePath, threadID: UInt16, cascade: Bool) async throws {}
    func createNewsBundle(at path: RemotePath, name: String, isCategory: Bool) async throws {}
    func postNewsThread(at path: RemotePath, parentThreadID: UInt16, title: String, type: String, body: String) async throws {}
    func listFiles(at path: RemotePath) async throws -> [RemoteFile] { [] }
    func deleteEntry(at path: RemotePath, name: String) async throws {}
    func createFolder(at path: RemotePath, name: String) async throws {}
    func fetchFileInfo(at path: RemotePath, name: String) async throws -> RemoteFileInfo {
        RemoteFileInfo(file: RemoteFile(name: name))
    }
    func updateFileMetadata(at path: RemotePath, name: String, change: FileMetadataChange) async throws {}
    func moveEntry(from sourcePath: RemotePath, name: String, to destinationPath: RemotePath) async throws {}
    func makeAlias(from sourcePath: RemotePath, name: String, to destinationPath: RemotePath) async throws {}
    func startDownload(at path: RemotePath, name: String, dataForkOffset: UInt32, resourceForkOffset: UInt32) async throws -> TransferHandle {
        TransferHandle(transferID: 0, totalSize: 0)
    }
    func startFolderDownload(at path: RemotePath, name: String) async throws -> TransferHandle {
        TransferHandle(transferID: 0, totalSize: 0)
    }
    func startUpload(at path: RemotePath, name: String, size: UInt32, resume: Bool) async throws -> TransferHandle {
        TransferHandle(transferID: 0, totalSize: 0)
    }
    func startFolderUpload(at path: RemotePath, name: String, size: UInt32, itemCount: UInt16, resume: Bool) async throws -> TransferHandle {
        TransferHandle(transferID: 0, totalSize: 0)
    }
    func cancelTransfer(_ handle: TransferHandle) async throws {}
    func downloadStream(for handle: TransferHandle) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func downloadEnvelope(for handle: TransferHandle) async throws -> UploadEnvelope {
        UploadEnvelope(fileName: "", data: Data(), type: .file, creator: .unknown)
    }
    var serverSupportsResourceForks: Bool { false }
    func consumeResourceFork(for transferID: UInt32) async -> Data { Data() }
    func sendUpload(_ content: Data, for handle: TransferHandle, fileName: String, type: HeidrunCore.FourCharCode, creator: HeidrunCore.FourCharCode, creationDate: Date, modificationDate: Date, resourceFork: Data, progress: (@Sendable (UInt64) async -> Void)?) async throws {}
    func sendFolderUpload(_ items: [FolderUploadItem], for handle: TransferHandle, type: HeidrunCore.FourCharCode, creator: HeidrunCore.FourCharCode, creationDate: Date, modificationDate: Date, progress: (@Sendable (UInt64) async -> Void)?) async throws {}
    func downloadBanner() async throws -> ServerBanner? { nil }
}

// MARK: - HostState test factory

/// Wraps `HostState.init` so every test gets its own scratch
/// `ActiveConnections` — no shared singleton, no `Heidrun.sessionRestoration`
/// snapshot pollution leaking into the next app launch. Production
/// `HostState()` defaults to `.shared`, which is fine for the app but a
/// landmine for tests that fan out fake servers with random UUID
/// addresses (one of those snapshots auto-reconnects on every launch
/// until cleaned up).
///
/// Matches the prod-side default connector when none is passed, so
/// tests that only assert on `lastAttemptedSettings` (set synchronously
/// before the connect Task fires) keep working.
@MainActor
func makeTestHostState(
    connector: HostState.Connector? = nil,
    autoReconnectCoordinator: AutoReconnectCoordinator = AutoReconnectCoordinator()
) -> HostState {
    let resolvedConnector: HostState.Connector = connector ?? { settings, _, _ in
        try await HotlineNetworkClient.connect(settings: settings)
    }
    return HostState(
        connections: ActiveConnections(),
        connector: resolvedConnector,
        autoReconnectCoordinator: autoReconnectCoordinator
    )
}

// MARK: - HostState test helpers

extension HostState {
    /// Spin until `.connecting` resolves into `.connected` or `.failed`,
    /// bounded so a stuck test fails fast instead of hanging.
    func waitForSettling(timeout: Duration = .seconds(1)) async {
        let deadline = ContinuousClock.now + timeout
        while case .connecting = phase, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Historically the connect Task parked on a 2-second no-agreement
    /// timeout, and this helper raced an `acceptAgreement()` poll
    /// against it. The Task no longer waits on the agreement at all
    /// (the sheet is now surfaced over the host view if/when trans=109
    /// arrives), so this helper is equivalent to `waitForSettling`.
    /// Kept as an alias so existing test call sites still read clearly.
    func acknowledgeAgreementWhenReady(timeout: Duration = .seconds(1)) async {
        await waitForSettling(timeout: timeout)
    }
}

// MARK: - Condition-based waiting

/// Poll `condition` every 5 ms until it holds or `timeout` elapses, then
/// return its final value. Replaces fixed `Task.sleep` guesses in the
/// auto-reconnect suites: the state they assert on is mutated inside a
/// spawned `Task { @MainActor in … }`, so a fixed window flakes when the
/// serial MainActor executor is saturated by other suites running in
/// parallel under a loaded machine (e.g. the all-tests scheme building +
/// testing every target at once). Waiting for the actual condition is
/// race-free yet returns the instant it is met.
@MainActor
@discardableResult
func poll(
    timeout: Duration = .seconds(2),
    until condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

// MARK: - Mutex

/// Tiny lock-protected value holder for tests that need a `Sendable`
/// counter or accumulator across closure boundaries.
final class Mutex<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ new: Value) { lock.lock(); value = new; lock.unlock() }
}
