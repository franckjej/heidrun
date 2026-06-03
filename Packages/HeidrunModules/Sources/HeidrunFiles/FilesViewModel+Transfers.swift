import Foundation
import HeidrunCore

/// Transfer machinery for `FilesViewModel`: downloads (with resume),
/// single-file uploads, recursive folder uploads, and the drain tasks
/// that keep the transfer drawer in sync with bytes on the wire.
extension FilesViewModel {
    public enum DownloadMode: Sendable {
        case fresh
        /// Use the existing on-disk size as `dataForkOffset`; new bytes
        /// append. Nothing on disk → equivalent to `.fresh`.
        case resume
    }

    // MARK: - Downloads

    /// True when a file with `entry.name` already exists at the download
    /// folder — drives the Replace / Resume / Cancel prompt.
    public func localFileExists(for entry: RemoteFile) -> Bool {
        let folder = downloadFolderURL()
        let started = folder.startAccessingSecurityScopedResource()
        defer { if started { folder.stopAccessingSecurityScopedResource() } }
        let urls = PartialDownloadURL(finalDestination: folder.appendingPathComponent(entry.name))
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: urls.partial.path)
            || fileManager.fileExists(atPath: urls.final.path)
    }

    /// Start a download, automatically resuming if a partial with the
    /// same name exists. Resume is the RFLT protocol intent: skip
    /// `dataForkOffset` bytes off the data fork; locally we open for
    /// appending so new bytes land after what's on disk. A partial as
    /// large or larger than `entry.size` is treated as already complete.
    public func download(_ entry: RemoteFile, mode: DownloadMode = .resume) async {
        await downloadInternal(entry, at: currentPath, mode: mode)
    }

    /// Re-issue from where the partial on disk left off. TaskManager's
    /// Resume button.
    public func resume(_ state: TransferState) async {
        guard state.direction == .download,
              let entry = state.sourceFile else { return }
        transfers.removeValue(forKey: state.handle.transferID)
        drainTasks.removeValue(forKey: state.handle.transferID)?.cancel()
        await downloadInternal(entry, at: state.sourcePath, mode: .resume)
    }

    private func downloadInternal(
        _ entry: RemoteFile,
        at path: RemotePath,
        mode: DownloadMode
    ) async {
        let folder = downloadFolderURL()
        let started = folder.startAccessingSecurityScopedResource()
        defer { if started { folder.stopAccessingSecurityScopedResource() } }

        let urls = PartialDownloadURL(finalDestination: folder.appendingPathComponent(entry.name))
        let onDiskSize = Self.partialSize(at: urls.partial)
        let legacySize = Self.partialSize(at: urls.final)

        let existingSize: UInt64
        switch mode {
        case .fresh:
            existingSize = 0
            // Drop any previous-run partial so fresh bytes don't append
            // onto stale ones.
            try? FileManager.default.removeItem(at: urls.partial)
        case .resume:
            existingSize = onDiskSize > 0 ? onDiskSize : legacySize
            if existingSize > 0, existingSize >= UInt64(entry.size) {
                return
            }
        }

        let resumeOffset = UInt32(clamping: existingSize)
        let handle: TransferHandle
        do {
            handle = try await beginDownload(path, entry.name, resumeOffset)
        } catch {
            lastError = String(describing: error)
            return
        }

        let state = TransferState(
            handle: handle,
            displayName: entry.name,
            destination: urls.final,
            direction: .download,
            sourcePath: path,
            sourceFile: entry,
            bytesWritten: existingSize,
            status: .running
        )
        transfers[handle.transferID] = state

        // Attach the resume xattr BEFORE the first byte hits disk.
        if let seed = metadataSeed() {
            let metadata = PartialDownloadMetadata(
                seed: seed,
                remotePath: path.components,
                remoteFileName: entry.name,
                totalSize: UInt64(entry.size)
            )
            try? FileManager.default.createDirectory(
                at: urls.partial.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: urls.partial.path) {
                try? Data().write(to: urls.partial)
            }
            try? PartialDownloadXattr.write(metadata, to: urls.partial)
        }

        drainTasks[handle.transferID] = Task { [weak self, folder, urls] in
            await self?.drainDownload(
                handle: handle,
                folder: folder,
                urls: urls,
                resumeOffset: existingSize,
                expectedTotalBytes: UInt64(entry.size)
            )
        }
    }

    private static func partialSize(at url: URL) -> UInt64 {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let sizeNumber = attrs[.size] as? NSNumber else { return 0 }
        return sizeNumber.uint64Value
    }

    private func drainDownload(
        handle: TransferHandle,
        folder: URL,
        urls: PartialDownloadURL,
        resumeOffset: UInt64,
        expectedTotalBytes: UInt64
    ) async {
        let started = folder.startAccessingSecurityScopedResource()
        defer { if started { folder.stopAccessingSecurityScopedResource() } }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: urls.partial.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            updateTransfer(id: handle.transferID) { state in
                state.status = .failed(
                    "couldn't create download folder: \(error.localizedDescription)"
                )
            }
            return
        }

        if resumeOffset == 0 || !fileManager.fileExists(atPath: urls.partial.path) {
            do {
                try Data().write(to: urls.partial, options: [])
            } catch {
                updateTransfer(id: handle.transferID) { state in
                    state.status = .failed(
                        "couldn't create \(urls.partial.lastPathComponent): \(error.localizedDescription)"
                    )
                }
                return
            }
        }
        guard let writer = try? FileHandle(forWritingTo: urls.partial) else {
            updateTransfer(id: handle.transferID) { state in
                state.status = .failed("couldn't open \(urls.partial.lastPathComponent) for writing")
            }
            return
        }
        defer { try? writer.close() }

        if resumeOffset > 0 {
            _ = try? writer.seekToEnd()
        }

        do {
            for try await chunk in downloadBytes(handle) {
                if Task.isCancelled { return }
                try writer.write(contentsOf: chunk)
                updateTransfer(id: handle.transferID) { state in
                    state.bytesWritten &+= UInt64(chunk.count)
                    state.recordSample(bytes: state.bytesWritten)
                }
            }
            try? writer.close()
            try Self.completePartialDownload(urls: urls, expectedTotalBytes: expectedTotalBytes)
            // Write the buffered rsrc to the renamed final file's named
            // fork. Empty rsrc / non-framed sessions are a no-op.
            let resourceFork = await consumeResourceFork(handle.transferID)
            if !resourceFork.isEmpty {
                let rsrcURL = urls.final.appendingPathComponent("..namedfork/rsrc")
                try? resourceFork.write(to: rsrcURL)
            }
            updateTransfer(id: handle.transferID) { state in
                state.status = .completed
            }
            if let finalState = transfers[handle.transferID] {
                onTransferFinished?(finalState)
            }
        } catch {
            updateTransfer(id: handle.transferID) { state in
                state.status = .failed(String(describing: error))
            }
        }
    }

    /// Strip the resume xattr and rename `.heidrunpart` → `<final>`. If
    /// the bytes-on-disk count is short, leave the partial so a resume
    /// can pick it up.
    private static func completePartialDownload(
        urls: PartialDownloadURL,
        expectedTotalBytes: UInt64
    ) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: urls.partial.path) else { return }
        let attrs = try fileManager.attributesOfItem(atPath: urls.partial.path)
        let actualSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        guard expectedTotalBytes == 0 || actualSize >= expectedTotalBytes else {
            return
        }
        try PartialDownloadXattr.remove(from: urls.partial)
        if fileManager.fileExists(atPath: urls.final.path) {
            try fileManager.removeItem(at: urls.final)
        }
        try fileManager.moveItem(at: urls.partial, to: urls.final)
    }

    /// Stream `entry` into `destination` for the row file-promise's
    /// `writePromiseTo`. AppKit calls it AFTER the drop, so streaming on
    /// the main actor can't deadlock Finder. Surfaces a TransferState
    /// like a regular download and rethrows on failure.
    public func downloadFile(_ entry: RemoteFile, at path: RemotePath, to destination: URL) async throws {
        let handle = try await beginDownload(path, entry.name, 0)
        transfers[handle.transferID] = TransferState(
            handle: handle,
            displayName: entry.name,
            destination: destination,
            direction: .download,
            sourcePath: path,
            sourceFile: entry,
            bytesWritten: 0,
            status: .running
        )
        do {
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: destination.path) {
                fileManager.createFile(atPath: destination.path, contents: nil)
            }
            let writer = try FileHandle(forWritingTo: destination)
            defer { try? writer.close() }
            for try await chunk in downloadBytes(handle) {
                try writer.write(contentsOf: chunk)
                updateTransfer(id: handle.transferID) { state in
                    state.bytesWritten &+= UInt64(chunk.count)
                    state.recordSample(bytes: state.bytesWritten)
                }
            }
            try? writer.close()
            // Carry the rsrc fork to the destination's named fork.
            let resourceFork = await consumeResourceFork(handle.transferID)
            if !resourceFork.isEmpty {
                let rsrcURL = destination.appendingPathComponent("..namedfork/rsrc")
                try? resourceFork.write(to: rsrcURL)
            }
            updateTransfer(id: handle.transferID) { $0.status = .completed }
            if let final = transfers[handle.transferID] { onTransferFinished?(final) }
        } catch {
            updateTransfer(id: handle.transferID) { $0.status = .failed(String(describing: error)) }
            throw error
        }
    }

    // MARK: - Uploads

    /// Push a local file. Defaults to `currentPath`; Replace / Resume
    /// hand an explicit `at:` so a re-issued upload survives the user
    /// navigating away while the conflict alert was up.
    public func upload(fileURL: URL, at explicitPath: RemotePath? = nil, resume: Bool = false) async {
        let fileManager = FileManager.default
        let name = fileURL.lastPathComponent
        guard !name.isEmpty else { return }

        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try fileManager.attributesOfItem(atPath: fileURL.path)
        } catch {
            lastError = String(describing: error)
            return
        }
        guard let sizeNumber = attrs[.size] as? NSNumber else {
            lastError = "could not read size of \(name)"
            return
        }
        let size = sizeNumber.uint64Value
        guard size <= UInt64(UInt32.max) else {
            lastError = "\(name) is larger than 4 GB and can't be uploaded yet"
            return
        }

        let content: Data
        do {
            // `.mappedIfSafe` avoids pulling huge files into RAM at once;
            // the chunked sender slices into 64KB windows over the map.
            content = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        } catch {
            lastError = String(describing: error)
            return
        }

        let handle: TransferHandle
        let targetPath = explicitPath ?? currentPath
        do {
            handle = try await beginUpload(targetPath, name, UInt32(size), resume)
        } catch let hotlineError as HotlineError {
            // Park the conflict so the view can present Replace / Resume
            // / Cancel. Snapshot `targetPath` for the same reason as
            // `replacePendingUpload` — the user can navigate away while
            // the alert is up.
            if case let .fileAlreadyExists(message) = hotlineError {
                pendingUploadConflict = PendingUploadConflict(
                    fileURL: fileURL,
                    targetPath: targetPath,
                    targetName: name,
                    serverMessage: message ?? "A file with that name already exists on the server."
                )
                return
            }
            lastError = hotlineError.userMessage
            return
        } catch {
            lastError = String(describing: error)
            return
        }

        // Real HFS type/creator codes: FinderInfo xattr if present (classic
        // Mac files), else the extension table. Without this Get Info
        // shows `????` / `....` on the server.
        let codes = HFSCodes.resolve(fileURL: fileURL)
        let createdAt = (attrs[.creationDate] as? Date) ?? Date()
        let modifiedAt = (attrs[.modificationDate] as? Date) ?? createdAt
        // Resource fork bytes from the file's macOS named fork. Empty
        // `Data()` for the 99% of files that have no rsrc.
        let resourceForkURL = fileURL.appendingPathComponent("..namedfork/rsrc")
        let resourceFork = (try? Data(contentsOf: resourceForkURL)) ?? Data()

        transfers[handle.transferID] = TransferState(
            handle: handle,
            displayName: name,
            destination: nil,
            direction: .upload,
            sourcePath: targetPath,
            sourceFile: nil,
            bytesWritten: 0,
            status: .running
        )
        drainTasks[handle.transferID] = Task { [weak self] in
            await self?.drainUpload(
                content: content,
                handle: handle,
                fileName: name,
                type: codes.type,
                creator: codes.creator,
                creationDate: createdAt,
                modificationDate: modifiedAt,
                resourceFork: resourceFork
            )
        }
    }

    /// Recursively upload `folderURL`. Walks the local tree once to build
    /// the per-item list + total size, then drives the legacy folder-
    /// upload framing (TX 213) over the side channel.
    public func uploadFolder(folderURL: URL) async {
        let folderName = folderURL.lastPathComponent
        guard !folderName.isEmpty else { return }

        let items: [FolderUploadItem]
        let totalSize: UInt64
        do {
            (items, totalSize) = try Self.collectFolderItems(at: folderURL)
        } catch {
            lastError = String(describing: error)
            return
        }
        guard !items.isEmpty else {
            lastError = "\(folderName) is empty — nothing to upload"
            return
        }
        guard totalSize <= UInt64(UInt32.max) else {
            lastError = "\(folderName) is larger than 4 GB and can't be uploaded yet"
            return
        }
        let itemCount = UInt16(clamping: items.count)

        let handle: TransferHandle
        do {
            handle = try await beginFolderUpload(currentPath, folderName, UInt32(totalSize), itemCount, false)
        } catch {
            lastError = String(describing: error)
            return
        }

        transfers[handle.transferID] = TransferState(
            handle: handle,
            displayName: folderName + "/",
            destination: nil,
            direction: .upload,
            sourcePath: currentPath,
            sourceFile: nil,
            bytesWritten: 0,
            status: .running
        )
        drainTasks[handle.transferID] = Task { [weak self] in
            await self?.drainFolderUpload(items: items, handle: handle)
        }
    }

    private func drainUpload(
        content: Data,
        handle: TransferHandle,
        fileName: String,
        type: HeidrunCore.FourCharCode,
        creator: HeidrunCore.FourCharCode,
        creationDate: Date,
        modificationDate: Date,
        resourceFork: Data
    ) async {
        let id = handle.transferID
        let totalSize = handle.totalSize
        let progress: @Sendable (UInt64) async -> Void = { [weak self] sent in
            await self?.applyUploadProgress(id: id, sent: sent, totalSize: totalSize)
        }
        do {
            try await sendUploadBytes(content, handle, fileName, type, creator, creationDate, modificationDate, resourceFork, progress)
            if Task.isCancelled { return }
            updateTransfer(id: id) { state in
                state.bytesWritten = totalSize
                state.status = .completed
            }
            if let final = transfers[id] {
                onTransferFinished?(final)
            }
        } catch {
            if Task.isCancelled { return }
            updateTransfer(id: id) { state in
                state.status = .failed(String(describing: error))
            }
        }
    }

    private func drainFolderUpload(items: [FolderUploadItem], handle: TransferHandle) async {
        let id = handle.transferID
        let totalSize = handle.totalSize
        let progress: @Sendable (UInt64) async -> Void = { [weak self] sent in
            await self?.applyUploadProgress(id: id, sent: sent, totalSize: totalSize)
        }
        do {
            try await sendFolderUploadBytes(items, handle, progress)
            if Task.isCancelled { return }
            updateTransfer(id: id) { state in
                state.bytesWritten = totalSize
                state.status = .completed
            }
            if let final = transfers[id] {
                onTransferFinished?(final)
            }
        } catch {
            if Task.isCancelled { return }
            updateTransfer(id: id) { state in
                state.status = .failed(String(describing: error))
            }
        }
    }

    /// Walk `folderURL` depth-first. Directories appear before their
    /// children — the legacy server needs parents on disk before files.
    private static func collectFolderItems(at folderURL: URL) throws -> ([FolderUploadItem], UInt64) {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            throw CocoaError(.fileReadUnknown)
        }
        let rootComponents = folderURL.standardizedFileURL.pathComponents
        var items: [FolderUploadItem] = []
        var totalSize: UInt64 = 0
        for case let url as URL in enumerator {
            let standardized = url.standardizedFileURL
            let values = try standardized.resourceValues(forKeys: keys)
            let isDirectory = values.isDirectory ?? false
            let pathComponents = standardized.pathComponents
            guard pathComponents.count > rootComponents.count else { continue }
            let relativePath = Array(pathComponents[rootComponents.count...])
            guard !relativePath.isEmpty else { continue }
            if isDirectory {
                items.append(FolderUploadItem(relativePath: relativePath, isDirectory: true))
            } else {
                let data = try Data(contentsOf: standardized, options: [.mappedIfSafe])
                items.append(FolderUploadItem(
                    relativePath: relativePath,
                    isDirectory: false,
                    data: data
                ))
                totalSize &+= UInt64(data.count)
            }
        }
        return (items, totalSize)
    }

    private func applyUploadProgress(id: UInt32, sent: UInt64, totalSize: UInt64) {
        updateTransfer(id: id) { state in
            state.bytesWritten = min(sent, totalSize)
            state.recordSample(bytes: state.bytesWritten)
        }
    }

    // MARK: - Upload-conflict resolution

    /// Replace the existing server file: delete then re-upload.
    ///
    /// **Takes `pending` as a parameter (not via `self.pendingUploadConflict`).**
    /// SwiftUI clears the alert's isPresented binding synchronously on
    /// the button tap, and our binding-set wires that to
    /// `cancelPendingUpload()` which nils the VM field BEFORE the
    /// dispatched Task runs — so a `guard let pending = pendingUploadConflict`
    /// would always fail and the delete would never reach the wire.
    ///
    /// Hotline TX 204 is fire-and-forget. To confirm the delete
    /// committed, follow up with `listFiles`; if the file is still
    /// present the delete was silently refused and we re-park the
    /// conflict with `replaceAttemptFailed`.
    public func replacePendingUpload(_ pending: PendingUploadConflict) async {
        pendingUploadConflict = nil
        do {
            try await deleteEntryAt(pending.targetPath, pending.targetName)
            let listing = try await listFiles(pending.targetPath)
            if listing.contains(where: { $0.name == pending.targetName }) {
                pendingUploadConflict = PendingUploadConflict(
                    fileURL: pending.fileURL,
                    targetPath: pending.targetPath,
                    targetName: pending.targetName,
                    serverMessage: pending.serverMessage,
                    replaceAttemptFailed: true
                )
                return
            }
        } catch {
            lastError = String(describing: error)
            return
        }
        await upload(fileURL: pending.fileURL, at: pending.targetPath, resume: false)
    }

    /// Re-issue with `resume=true`. Takes the conflict as a parameter
    /// for the same SwiftUI alert-binding-race reason as `replacePendingUpload`.
    public func resumePendingUpload(_ pending: PendingUploadConflict) async {
        pendingUploadConflict = nil
        await upload(fileURL: pending.fileURL, at: pending.targetPath, resume: true)
    }

    public func cancelPendingUpload() {
        pendingUploadConflict = nil
    }

    // MARK: - Cancel / cleanup

    public func cancel(_ handle: TransferHandle) async {
        drainTasks.removeValue(forKey: handle.transferID)?.cancel()
        do {
            try await cancelTransferAt(handle)
            transfers.removeValue(forKey: handle.transferID)
        } catch { lastError = String(describing: error) }
    }

    public func clearFinishedTransfers() {
        transfers = transfers.filter { _, state in
            state.status == .running
        }
    }

    func updateTransfer(id: UInt32, mutate: (inout TransferState) -> Void) {
        guard var state = transfers[id] else { return }
        mutate(&state)
        transfers[id] = state
    }
}
