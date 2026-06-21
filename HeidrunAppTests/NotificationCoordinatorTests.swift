import Foundation
import Testing
@testable import Heidrun
@testable import HeidrunUI
import HeidrunChat
import HeidrunCore

@MainActor
@Suite("NotificationCoordinator routing")
struct NotificationCoordinatorTests {
    @Test("broadcastReceived posts .broadcast with the host identity")
    func broadcastReceivedPostsBroadcastNotification() async {
        let client = FakeRoutingClient()
        let service = RecordingNotificationPoster()
        let host = HostIdentity(id: "host-route", displayName: "TastyBytes")
        let coordinator = NotificationCoordinator(
            client: client,
            host: host,
            userList: UserListViewModel(client: client),
            service: service
        )

        await coordinator.start()
        client.emit(.broadcastReceived(message: "downtime imminent"))

        await waitFor { service.posts.count == 1 }
        coordinator.cancel()

        #expect(service.posts.count == 1)
        guard case let .broadcast(text) = service.posts.first?.event else {
            Issue.record("expected .broadcast event")
            return
        }
        #expect(text == "downtime imminent")
        #expect(service.posts.first?.host == host)
    }

    @Test("other events do NOT post a broadcast")
    func otherEventsDoNotPostBroadcast() async {
        let client = FakeRoutingClient()
        let service = RecordingNotificationPoster()
        let coordinator = NotificationCoordinator(
            client: client,
            host: HostIdentity(id: "host-other", displayName: "Other"),
            userList: UserListViewModel(client: client),
            service: service
        )
        await coordinator.start()

        client.emit(.userListReceived(users: []))
        client.emit(.chatReceived(chat: nil, message: "x", isAction: false))
        try? await Task.sleep(for: .milliseconds(30))
        coordinator.cancel()

        #expect(service.posts.allSatisfy { post in
            if case .broadcast = post.event { return false }
            return true
        })
    }

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

@MainActor
private final class RecordingNotificationPoster: NotificationPosting {
    struct Post {
        let event: NotificationCenterService.Event
        let host: HostIdentity
    }
    var posts: [Post] = []
    func post(_ event: NotificationCenterService.Event, host: HostIdentity) async {
        posts.append(Post(event: event, host: host))
    }
}

private final class FakeRoutingClient: HotlineClient, @unchecked Sendable {
    let events: AsyncStream<HotlineEvent>
    private let continuation: AsyncStream<HotlineEvent>.Continuation

    init() {
        var cont: AsyncStream<HotlineEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }
    func emit(_ event: HotlineEvent) { continuation.yield(event) }

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
    func startUpload(at path: RemotePath, name: String, size: UInt64, resume: Bool) async throws -> TransferHandle {
        TransferHandle(transferID: 0, totalSize: 0)
    }
    func startFolderUpload(at path: RemotePath, name: String, size: UInt64, itemCount: UInt16, resume: Bool) async throws -> TransferHandle {
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
