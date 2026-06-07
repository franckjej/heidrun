import Foundation
import Observation
import HeidrunCore

/// Remote-file browser VM: current path, listing, in-flight transfers.
/// Transfer machinery lives in `FilesViewModel+Transfers.swift`; the
/// in-memory Quick Look pipeline in `FilesViewModel+Preview.swift`.
@Observable
@MainActor
public final class FilesViewModel {
    public internal(set) var currentPath: RemotePath = []
    public internal(set) var files: [RemoteFile] = []
    public internal(set) var isLoading: Bool = false

    /// The connected account's own privileges (from the server's "User
    /// Access" push, fed by the host). UI hint only — the server still
    /// enforces every file op. `hasPrivilegeInfo` stays false until the
    /// server tells us, so `permits` is **fail-open** (controls enabled)
    /// against servers that don't advertise privileges.
    public internal(set) var selfPrivileges: UserPrivileges = []
    public internal(set) var hasPrivilegeInfo: Bool = false

    /// Called by the host when the "User Access" push arrives.
    public func updatePrivileges(_ privileges: UserPrivileges) {
        selfPrivileges = privileges
        hasPrivilegeInfo = true
    }

    /// Enabled unless we KNOW the account lacks `privilege`.
    public func permits(_ privilege: UserPrivileges) -> Bool {
        !hasPrivilegeInfo || selfPrivileges.contains(privilege)
    }

    /// Finished entries stay until `clearFinishedTransfers()` so the UI
    /// can show "done" rows.
    public internal(set) var transfers: [UInt32: TransferState] = [:]

    /// Set when `upload(fileURL:resume:)` surfaces a `.fileAlreadyExists`.
    public internal(set) var pendingUploadConflict: PendingUploadConflict?

    /// Carries everything needed to re-issue the upload so the user can
    /// navigate away while the alert sits.
    public struct PendingUploadConflict: Identifiable, Sendable {
        public let id = UUID()
        public let fileURL: URL
        public let targetPath: RemotePath
        public let targetName: String
        public let serverMessage: String
        /// `true` after Replace was tapped but the server still reports
        /// the file. Flips alert wording to "couldn't delete it" so the
        /// user knows to check permissions rather than tap Replace forever.
        public let replaceAttemptFailed: Bool

        public init(
            fileURL: URL,
            targetPath: RemotePath,
            targetName: String,
            serverMessage: String,
            replaceAttemptFailed: Bool = false
        ) {
            self.fileURL = fileURL
            self.targetPath = targetPath
            self.targetName = targetName
            self.serverMessage = serverMessage
            self.replaceAttemptFailed = replaceAttemptFailed
        }
    }

    public internal(set) var previewState: PreviewState = .idle

    /// Larger files fall back to the regular Download path.
    public static let maxPreviewBytes: UInt64 = 5 * 1024 * 1024

    /// Conservative — anything missing still works via Download.
    public static let previewableTextExtensions: Set<String> = [
        "txt", "md", "markdown", "log", "json", "xml",
        "html", "htm", "css", "js", "swift", "c", "cpp",
        "h", "hpp", "m", "mm", "py", "rb", "sh", "yaml",
        "yml", "conf", "ini", "cfg", "csv", "tsv", "plist",
        "tex", "ts", "tsx", "jsx", "go", "rs", "java", "kt",
        "kts", "toml", "rst", "asc", "diff", "patch", "sql"
    ]

    public static func isPreviewable(_ entry: RemoteFile) -> Bool {
        guard !entry.isFolder, !entry.isUnresolvedAlias else { return false }
        let fileExtension = (entry.name as NSString).pathExtension.lowercased()
        if previewableTextExtensions.contains(fileExtension) { return true }
        // Classic Mac "TEXT" — extension-less files on older Hotline trees
        // where the HFS type carries the only hint.
        return entry.type.stringValue == "TEXT"
    }

    var previewTask: Task<Void, Never>?
    var previewHandle: TransferHandle?

    public typealias UploadProgress = @Sendable (UInt64) async -> Void
    public typealias UploadSender = @Sendable (
        _ content: Data,
        _ handle: TransferHandle,
        _ fileName: String,
        _ type: HeidrunCore.FourCharCode,
        _ creator: HeidrunCore.FourCharCode,
        _ creationDate: Date,
        _ modificationDate: Date,
        _ resourceFork: Data,
        _ progress: @escaping UploadProgress
    ) async throws -> Void
    public typealias FolderUploadSender = @Sendable (
        _ items: [FolderUploadItem],
        _ handle: TransferHandle,
        _ progress: @escaping UploadProgress
    ) async throws -> Void

    let listFiles: @Sendable (RemotePath) async throws -> [RemoteFile]
    let createFolderAt: @Sendable (RemotePath, String) async throws -> Void
    let deleteEntryAt: @Sendable (RemotePath, String) async throws -> Void
    let renameAt: @Sendable (RemotePath, String, String) async throws -> Void
    let setCommentAt: @Sendable (RemotePath, String, String) async throws -> Void
    let moveEntryAt: @Sendable (RemotePath, String, RemotePath) async throws -> Void
    let fetchFileInfoAt: @Sendable (RemotePath, String) async throws -> RemoteFileInfo
    let beginDownload: @Sendable (RemotePath, String, UInt32) async throws -> TransferHandle
    let beginUpload: @Sendable (RemotePath, String, UInt32, Bool) async throws -> TransferHandle
    let beginFolderUpload: @Sendable (RemotePath, String, UInt32, UInt16, Bool) async throws -> TransferHandle
    let cancelTransferAt: @Sendable (TransferHandle) async throws -> Void
    let downloadBytes: @Sendable (TransferHandle) -> AsyncThrowingStream<Data, Error>
    /// Returns empty `Data` for non-framed transfers or no-rsrc files.
    let consumeResourceFork: @Sendable (UInt32) async -> Data
    let sendUploadBytes: UploadSender
    let sendFolderUploadBytes: FolderUploadSender
    let downloadFolderURL: @Sendable () -> URL
    let onTransferFinished: (@MainActor @Sendable (TransferState) -> Void)?
    let metadataSeed: @Sendable () -> PartialDownloadMetadata.SeedFields?
    let present: @MainActor (Error) -> Void

    /// Tests verify callers actually wired a seed instead of letting it
    /// default to `{ nil }`, which would silently break the resume xattr.
    public func currentMetadataSeed() -> PartialDownloadMetadata.SeedFields? {
        metadataSeed()
    }

    var drainTasks: [UInt32: Task<Void, Never>] = [:]

    public init(
        listFiles: @escaping @Sendable (RemotePath) async throws -> [RemoteFile],
        createFolderAt: @escaping @Sendable (RemotePath, String) async throws -> Void,
        deleteEntryAt: @escaping @Sendable (RemotePath, String) async throws -> Void,
        renameAt: @escaping @Sendable (RemotePath, String, String) async throws -> Void,
        setCommentAt: @escaping @Sendable (RemotePath, String, String) async throws -> Void,
        moveEntryAt: @escaping @Sendable (RemotePath, String, RemotePath) async throws -> Void,
        fetchFileInfoAt: @escaping @Sendable (RemotePath, String) async throws -> RemoteFileInfo,
        beginDownload: @escaping @Sendable (RemotePath, String, UInt32) async throws -> TransferHandle,
        beginUpload: @escaping @Sendable (RemotePath, String, UInt32, Bool) async throws -> TransferHandle,
        beginFolderUpload: @escaping @Sendable (RemotePath, String, UInt32, UInt16, Bool) async throws -> TransferHandle
            = { _, _, _, _, _ in throw HotlineError.notConnected },
        cancelTransferAt: @escaping @Sendable (TransferHandle) async throws -> Void,
        downloadBytes: @escaping @Sendable (TransferHandle) -> AsyncThrowingStream<Data, Error>
            = { _ in AsyncThrowingStream { $0.finish() } },
        consumeResourceFork: @escaping @Sendable (UInt32) async -> Data
            = { _ in Data() },
        sendUploadBytes: @escaping UploadSender = { _, _, _, _, _, _, _, _, _ in },
        sendFolderUploadBytes: @escaping FolderUploadSender = { _, _, _ in },
        downloadFolderURL: @escaping @Sendable () -> URL = FilesViewModel.defaultDownloadFolder,
        onTransferFinished: (@MainActor @Sendable (TransferState) -> Void)? = nil,
        metadataSeed: @escaping @Sendable () -> PartialDownloadMetadata.SeedFields? = { nil },
        present: @escaping @MainActor (Error) -> Void = { _ in }
    ) {
        self.listFiles            = listFiles
        self.createFolderAt       = createFolderAt
        self.deleteEntryAt        = deleteEntryAt
        self.renameAt             = renameAt
        self.setCommentAt         = setCommentAt
        self.moveEntryAt          = moveEntryAt
        self.fetchFileInfoAt      = fetchFileInfoAt
        self.beginDownload        = beginDownload
        self.beginUpload          = beginUpload
        self.beginFolderUpload    = beginFolderUpload
        self.cancelTransferAt     = cancelTransferAt
        self.downloadBytes        = downloadBytes
        self.consumeResourceFork  = consumeResourceFork
        self.sendUploadBytes      = sendUploadBytes
        self.sendFolderUploadBytes = sendFolderUploadBytes
        self.downloadFolderURL    = downloadFolderURL
        self.onTransferFinished   = onTransferFinished
        self.metadataSeed         = metadataSeed
        self.present              = present
    }

    public convenience init(
        client: any HotlineClient,
        downloadFolderURL: @escaping @Sendable () -> URL = FilesViewModel.defaultDownloadFolder,
        onTransferFinished: (@MainActor @Sendable (TransferState) -> Void)? = nil,
        metadataSeed: @escaping @Sendable () -> PartialDownloadMetadata.SeedFields? = { nil },
        present: @escaping @MainActor (Error) -> Void = { _ in }
    ) {
        self.init(
            listFiles: { [client] path in
                try await client.listFiles(at: path)
            },
            createFolderAt: { [client] path, name in
                try await client.createFolder(at: path, name: name)
            },
            deleteEntryAt: { [client] path, name in
                try await client.deleteEntry(at: path, name: name)
            },
            renameAt: { [client] path, name, newName in
                try await client.updateFileMetadata(at: path, name: name, change: .rename(newName: newName))
            },
            setCommentAt: { [client] path, name, comment in
                try await client.updateFileMetadata(at: path, name: name, change: .comment(newComment: comment))
            },
            moveEntryAt: { [client] from, name, to in
                try await client.moveEntry(from: from, name: name, to: to)
            },
            fetchFileInfoAt: { [client] path, name in
                try await client.fetchFileInfo(at: path, name: name)
            },
            beginDownload: { [client] path, name, offset in
                try await client.startDownload(at: path, name: name, dataForkOffset: offset, resourceForkOffset: 0)
            },
            beginUpload: { [client] path, name, size, resume in
                try await client.startUpload(at: path, name: name, size: size, resume: resume)
            },
            beginFolderUpload: { [client] path, name, size, itemCount, resume in
                try await client.startFolderUpload(
                    at: path,
                    name: name,
                    size: size,
                    itemCount: itemCount,
                    resume: resume
                )
            },
            cancelTransferAt: { [client] handle in
                try await client.cancelTransfer(handle)
            },
            downloadBytes: { [client] handle in
                client.downloadStream(for: handle)
            },
            consumeResourceFork: { [client] transferID in
                await client.consumeResourceFork(for: transferID)
            },
            sendUploadBytes: { [client] content, handle, fileName, type, creator, created, modified, resourceFork, progress in
                try await client.sendUpload(
                    content,
                    for: handle,
                    fileName: fileName,
                    type: type,
                    creator: creator,
                    creationDate: created,
                    modificationDate: modified,
                    resourceFork: resourceFork,
                    progress: progress
                )
            },
            sendFolderUploadBytes: { [client] items, handle, progress in
                try await client.sendFolderUpload(items, for: handle, progress: progress)
            },
            downloadFolderURL: downloadFolderURL,
            onTransferFinished: onTransferFinished,
            metadataSeed: metadataSeed,
            present: present
        )
    }

    nonisolated public static func defaultDownloadFolder() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    // MARK: - Navigation

    public func navigate(to path: RemotePath) async {
        currentPath = path
        await refresh()
    }

    public func navigateInto(_ entry: RemoteFile) async {
        guard entry.isFolder else { return }
        await navigate(to: currentPath.appending(entry.name))
    }

    public func navigateUp() async {
        guard !currentPath.isRoot else { return }
        await navigate(to: currentPath.parent)
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            files = try await listFiles(currentPath)
        } catch {
            present(error)
            files = []
        }
    }

    // MARK: - Mutations

    public func createFolder(named name: String) async {
        guard !name.isEmpty else { return }
        do {
            try await createFolderAt(currentPath, name)
            await refresh()
        } catch { present(error) }
    }

    public func delete(_ entry: RemoteFile) async {
        do {
            try await deleteEntryAt(currentPath, entry.name)
            await refresh()
        } catch { present(error) }
    }

    /// Batch delete with one trailing refresh (vs N round-trips). Stops
    /// on the first failure, matching `delete(_:)`'s behaviour.
    public func deleteAll(_ entries: [RemoteFile]) async {
        guard !entries.isEmpty else { return }
        do {
            for entry in entries {
                try await deleteEntryAt(currentPath, entry.name)
            }
            await refresh()
        } catch { present(error) }
    }

    public func rename(_ entry: RemoteFile, to newName: String) async {
        guard !newName.isEmpty, newName != entry.name else { return }
        do {
            try await renameAt(currentPath, entry.name, newName)
            await refresh()
        } catch { present(error) }
    }

    public func setComment(on entry: RemoteFile, _ comment: String) async {
        do {
            try await setCommentAt(currentPath, entry.name, comment)
            await refresh()
        } catch { present(error) }
    }

    public func move(_ entry: RemoteFile, to destination: RemotePath) async {
        do {
            try await moveEntryAt(currentPath, entry.name, destination)
            await refresh()
        } catch { present(error) }
    }

    public func fetchFileInfo(_ entry: RemoteFile) async throws -> RemoteFileInfo {
        try await fetchFileInfoAt(currentPath, entry.name)
    }
}
