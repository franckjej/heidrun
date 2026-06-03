import Foundation
import Testing
@testable import Heidrun
import HeidrunCore
import HeidrunFiles

/// Regression coverage for the `metadataSeed` wiring `ConnectionHandle`
/// hands to its `FilesViewModel`. The closure is what stamps every
/// `.heidrunpart` file with the server identity that produced it; if
/// the seed is missing the xattr never gets written and Finder
/// double-click later trips the "Couldn't read resume info" sheet for
/// every partial download. The bug that prompted this test was exactly
/// that: `ConnectionHandle.init` constructed `FilesViewModel` without
/// the `metadataSeed:` argument, so the parameter defaulted to `{ nil }`
/// in production.
///
/// These tests poke the static helper directly so the assertion is
/// independent of the `FilesViewModel` internals. If `ConnectionHandle.init`
/// regresses to constructing `FilesViewModel` without a seed (or with
/// the default `{ nil }`), the integration-style test below — which
/// reaches through the real init path — fails.
@Suite("ConnectionHandle.metadataSeed")
struct ConnectionHandleTests {
    private func makeSettings(
        name: String = "Carpe Diem",
        address: String = "hl.example.com",
        port: UInt16 = 5500,
        login: String = "guest"
    ) -> ConnectionSettings {
        ConnectionSettings(
            name: name,
            address: address,
            port: port,
            nickname: "tester",
            login: login
        )
    }

    @Test("static helper produces a seed matching the settings")
    func staticHelperMatchesSettings() {
        let settings = makeSettings(
            name: "Carpe Diem",
            address: "hl.example.com",
            port: 5501,
            login: "jens"
        )

        let producer = ConnectionHandle.metadataSeed(for: settings)
        let seed = producer()

        #expect(seed != nil)
        #expect(seed?.serverAddress == "hl.example.com")
        #expect(seed?.serverPort == 5501)
        #expect(seed?.serverLogin == "jens")
        #expect(seed?.serverName == "Carpe Diem")
    }

    @Test("static helper falls back to address when settings.name is empty")
    func staticHelperFallsBackToAddressForEmptyName() {
        let settings = makeSettings(name: "", address: "hl.example.com")

        let seed = ConnectionHandle.metadataSeed(for: settings)()

        // Resume sheet renders "From <serverName>" — empty reads badly,
        // so we mirror the `displayName` convention.
        #expect(seed?.serverName == "hl.example.com")
    }

    @Test("static helper preserves empty server login as empty (guest)")
    func staticHelperPreservesEmptyGuestLogin() {
        let settings = makeSettings(login: "")
        let seed = ConnectionHandle.metadataSeed(for: settings)()
        #expect(seed?.serverLogin.isEmpty == true)
    }

    /// Integration-style: drives the real `ConnectionHandle.init` path
    /// the production app uses. If a future refactor drops the
    /// `metadataSeed:` argument from the `FilesViewModel(...)` call in
    /// `ConnectionHandle.init`, the parameter defaults to `{ nil }`,
    /// `currentMetadataSeed()` returns `nil`, and this test fails —
    /// which is the regression we're guarding.
    @MainActor
    @Test("ConnectionHandle.init wires metadataSeed through to FilesViewModel")
    func connectionHandleInitWiresMetadataSeed() {
        let settings = makeSettings(
            name: "Carpe Diem",
            address: "hl.example.com",
            port: 5502,
            login: "guest"
        )
        let client = ConnectionHandleFakeClient()
        let handle = ConnectionHandle(settings: settings, client: client)

        // Pull the seed from the FilesViewModel the handle actually built.
        // This is the closure the production download path will call when
        // it stamps `.heidrunpart` xattrs, so seeing the expected fields
        // here proves the wiring is alive end-to-end.
        let seed = handle.filesVM.currentMetadataSeed()
        #expect(seed != nil, "FilesViewModel.metadataSeed returned nil — ConnectionHandle.init regressed to the default closure")
        #expect(seed?.serverAddress == "hl.example.com")
        #expect(seed?.serverPort == 5502)
        #expect(seed?.serverLogin == "guest")
        #expect(seed?.serverName == "Carpe Diem")
    }

    @MainActor
    @Test("ConnectionHandle.init seeds the FilesViewModel with the address fallback when name is empty")
    func connectionHandleInitFallsBackToAddressForEmptyName() {
        let settings = makeSettings(name: "", address: "hl.example.com")
        let handle = ConnectionHandle(settings: settings, client: ConnectionHandleFakeClient())
        let seed = handle.filesVM.currentMetadataSeed()
        #expect(seed?.serverName == "hl.example.com")
    }
}

// MARK: - Test helpers

/// Minimal fake client so `ConnectionHandle.init` can be exercised in a
/// unit test. Every transaction is a no-op — the test never calls anything
/// that hits the wire.
private final class ConnectionHandleFakeClient: HotlineClient, @unchecked Sendable {
    let events: AsyncStream<HotlineEvent>
    private let continuation: AsyncStream<HotlineEvent>.Continuation

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

    init() {
        var stashedContinuation: AsyncStream<HotlineEvent>.Continuation!
        self.events = AsyncStream { stashedContinuation = $0 }
        self.continuation = stashedContinuation
    }

    func disconnect() async { continuation.finish() }
    func requestAttention(_ flags: AttentionFlags) async {}
    func sendPing() async throws {}
    func login(name: String, password: String, nickname: String, icon: UInt16, emoji: String?) async throws {}
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
