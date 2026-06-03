import Foundation
import Testing
@testable import HeidrunUI
import HeidrunCore

@MainActor
@Suite("BroadcastViewModel")
struct BroadcastViewModelTests {
    @Test("pending starts empty; current is nil")
    func pendingStartsEmpty() {
        let client = FakeBroadcastClient()
        let viewModel = BroadcastViewModel(client: client)
        #expect(viewModel.pending.isEmpty)
        #expect(viewModel.current == nil)
    }

    @Test("yielding .broadcastReceived appends to pending; current reflects the head")
    func broadcastReceivedAppendsToPending() async {
        let client = FakeBroadcastClient()
        let viewModel = BroadcastViewModel(client: client)
        await viewModel.start()

        client.emit(.broadcastReceived(message: "first"))
        client.emit(.broadcastReceived(message: "second"))
        client.emit(.broadcastReceived(message: "third"))

        await waitFor { viewModel.pending.count == 3 }

        #expect(viewModel.pending.map(\.message) == ["first", "second", "third"])
        #expect(viewModel.current?.message == "first")
    }

    @Test("unrelated events are ignored")
    func unrelatedEventsAreIgnored() async {
        let client = FakeBroadcastClient()
        let viewModel = BroadcastViewModel(client: client)
        await viewModel.start()

        client.emit(.chatReceived(chat: nil, message: "hi", isAction: false))
        client.emit(.userListReceived(users: []))
        client.emit(.newsPosted(text: "news"))

        // Give the stream a chance to deliver; absence of work means
        // `pending` stays empty.
        try? await Task.sleep(for: .milliseconds(20))
        #expect(viewModel.pending.isEmpty)
    }

    @Test("dismissCurrent on empty queue is a no-op")
    func dismissCurrentEmptyIsNoOp() {
        let client = FakeBroadcastClient()
        let viewModel = BroadcastViewModel(client: client)
        viewModel.dismissCurrent()
        #expect(viewModel.pending.isEmpty)
        #expect(viewModel.current == nil)
    }

    @Test("dismissCurrent pops the head")
    func dismissCurrentPopsHead() async {
        let client = FakeBroadcastClient()
        let viewModel = BroadcastViewModel(client: client)
        await viewModel.start()

        client.emit(.broadcastReceived(message: "only"))
        await waitFor { viewModel.pending.count == 1 }

        viewModel.dismissCurrent()
        #expect(viewModel.pending.isEmpty)
        #expect(viewModel.current == nil)
    }

    @Test("dismissCurrent advances to the next entry")
    func dismissCurrentAdvancesToNext() async {
        let client = FakeBroadcastClient()
        let viewModel = BroadcastViewModel(client: client)
        await viewModel.start()

        client.emit(.broadcastReceived(message: "first"))
        client.emit(.broadcastReceived(message: "second"))
        await waitFor { viewModel.pending.count == 2 }

        viewModel.dismissCurrent()
        #expect(viewModel.current?.message == "second")
        #expect(viewModel.pending.map(\.message) == ["second"])
    }

    @Test("cancel stops the listen loop; further yields don't append")
    func cancelStopsListening() async {
        let client = FakeBroadcastClient()
        let viewModel = BroadcastViewModel(client: client)
        await viewModel.start()

        client.emit(.broadcastReceived(message: "before-cancel"))
        await waitFor { viewModel.pending.count == 1 }

        viewModel.cancel()
        client.emit(.broadcastReceived(message: "after-cancel"))
        // Cancellation is best-effort against an in-flight iteration; allow a
        // brief settle window before asserting.
        try? await Task.sleep(for: .milliseconds(30))
        #expect(viewModel.pending.map(\.message) == ["before-cancel"])
    }

    /// Polling wait — VM updates land on the main actor through the
    /// async stream loop, so a small sleep-poll keeps the test snappy
    /// without flake risk on slow CI. 0.5s cap.
    private func waitFor(
        timeout: Duration = .milliseconds(500),
        predicate: @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !predicate(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

// MARK: - Test helpers

private final class FakeBroadcastClient: HotlineClient, @unchecked Sendable {
    let events: AsyncStream<HotlineEvent>
    private let continuation: AsyncStream<HotlineEvent>.Continuation

    init() {
        var cont: AsyncStream<HotlineEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    func emit(_ event: HotlineEvent) { continuation.yield(event) }
    func finishEvents() { continuation.finish() }

    var connectionInfo: HotlineConnectionInfo {
        get async {
            HotlineConnectionInfo(
                clientVersion: 0,
                protocolVersion: 0,
                connectionSocket: 0,
                lastTaskNumber: 0,
                settings: ConnectionSettings(name: "", address: "")
            )
        }
    }
    func disconnect() async {}
    func requestAttention(_ flags: AttentionFlags) async {}
    func sendPing() async throws {}
    func login(name: String, password: String, nickname: String, icon: UInt16, emoji: String?) async throws {}
    func agreeToAgreement(nickname: String, icon: UInt16, emoji: String?) async throws {}
    func changeNickname(_ nickname: String, icon: UInt16, emoji: String?, persist: Bool) async throws {}
    func fetchUserList() async throws -> [User] { [] }
    func fetchUserInfo(socket: UInt16) async throws -> UserInfo {
        UserInfo(user: User(socket: 0), infoText: "")
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
    func sendUpload(_ content: Data, for handle: TransferHandle, fileName: String, type: HeidrunCore.FourCharCode, creator: HeidrunCore.FourCharCode, creationDate: Date, modificationDate: Date, progress: (@Sendable (UInt64) async -> Void)?) async throws {}
    func sendFolderUpload(_ items: [FolderUploadItem], for handle: TransferHandle, type: HeidrunCore.FourCharCode, creator: HeidrunCore.FourCharCode, creationDate: Date, modificationDate: Date, progress: (@Sendable (UInt64) async -> Void)?) async throws {}
    func downloadBanner() async throws -> ServerBanner? { nil }
}
